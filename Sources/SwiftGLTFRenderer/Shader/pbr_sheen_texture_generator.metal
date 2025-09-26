#include <metal_stdlib>
#include "includes/helper.h"
#include "../../SwiftGLTFShaderTypes/includes/pbr.h"

using namespace metal;

// Remap sheen roughness to avoid too sharp highlights
inline float remapSheenRoughness(float r) {
    // ensure at least 0.07
    return clamp(0.5*r + 0.5*r*r, 0.07, 1.0);
}

inline float3 toWorld(float3 h, float3 N)
{
    float3 up = (abs(N.z) < 0.999) ? float3(0,0,1) : float3(1,0,0);
    float3 T  = normalize(cross(up, N));
    float3 B  = cross(N, T);
    return normalize(T*h.x + B*h.y + N*h.z);
}

inline float D_Charlie(float NoH, float alpha)
{
    alpha = clamp(alpha, 0.07, 1.0);
    float invA = 1.0 / alpha;
    float c    = max(NoH, 1e-5);
    // ((2 + 1/alpha) / (2π)) * (cosθ)^(1/alpha)
    return ((2.0 + invA) * pow(c, invA)) * (0.5f / M_PI_F);
}

// outPdfH: p(H) = D(H) * (N⋅H)
inline float3 sampleHalfVectorCharlie(float2 xi, float3 N, float a, thread float* outPdfH)
{
    a = clamp(a, 0.07, 1.0);
    float invA  = 1.0 / a;
    float phi   = 2.0f * M_PI_F * xi.x;
    // cosθ = (1 - u.y)^(1/(2 + 1/α))
    float cosT  = pow(1.0f - xi.y, 1.0f / (2.0f + invA));
    float sinT  = sqrt(1.0f - cosT * cosT);
    float3 Ht   = float3(cos(phi)*sinT, sin(phi)*sinT, cosT);
    float3 H    = toWorld(Ht, N);

    float NoH = max(dot(N, H), 1e-6f);
    if (outPdfH) *outPdfH = D_Charlie(NoH, a) * NoH;
    return H;
}

kernel void prefilterSheenEnvMap(texturecube<float, access::sample> envMap   [[texture(0)]],
                                 texturecube<float, access::write>  outMap   [[texture(1)]],
                                 constant PreFilterSheenEnvMapParams &params [[buffer(0)]],
                                 uint3 gid [[thread_position_in_grid]])
{
    if (gid.x >= params.cubeSize || gid.y >= params.cubeSize) return;

    float2 uv = (float2(gid.xy) + 0.5) / float(params.cubeSize) * 2.0 - 1.0; // Convert to [-1, 1] range
    float3 R  = getDirectionForFace(gid.z, uv);
    float3 N  = normalize(R);
    float3 V  = N;

    constexpr sampler s(filter::linear, mip_filter::linear);

    float  rSheen = remapSheenRoughness(params.roughness);
    float3 prefiltered = float3(0.0);

    // H ~ Charlie(D)、 L = reflect(-V,H)
    for (uint i = 0; i < params.sampleCount; ++i) {
        float2 xi   = hammersley(i, params.sampleCount);
        float  pdfH = 0.0f;
        float3 H    = sampleHalfVectorCharlie(xi, N, rSheen, &pdfH);
        float3 L    = normalize(reflect(-V, H));

        float NdotL = max(dot(N, L), 0.0f);
        if (NdotL <= 0.0f) continue;

        float VdotH = max(dot(V, H), 1e-5f);

        // H→L の pdf 変換： p(L) = p(H) / (4 * (V⋅H))
        float pdfL  = pdfH / 4.0f * VdotH;

        // モンテカルロ重み： 1 / p(L)
        float w = 1 / pdfL;

        float3 Li = envMap.sample(s, L, level(0)).rgb * NdotL;

        prefiltered += Li * w;
    }

    prefiltered = prefiltered / float(params.sampleCount);

    outMap.write(float4(prefiltered, 1.0), gid.xy, gid.z, params.mipLevel);
}
