#include <metal_stdlib>
#include "includes/helper.h"
#include "../../SwiftGLTFShaderTypes/includes/pbr.h"

using namespace metal;

// Remap sheen roughness to avoid too sharp highlights
inline float remapSheenRoughness(float r) {
    // ensure at least 0.07
    return clamp(0.5*r + 0.5*r*r, 0.07, 1.0);
}

inline float texelSolidAngleApprox(uint faceSize /* side length in pixels */) {
    // 平均立体角: 4π / (6 * S^2)
    return (4.0f * M_PI_F) / (6.0f * float(faceSize) * float(faceSize));
}

inline float mipFromSolidAngle(float saSample, float saTexel) {
    // saSample / saTexel の面積比 → LOD
    return 0.5f * log2(max(saSample / max(saTexel, 1e-12f), 1e-12f));
}

inline float optimizeMipLevel(float pdfL,
                              uint cubeSize,
                              uint mipLevel,
                              uint sampleCount,
                              float envMaxMip)
{
    // いま書き込む outMap の face サイズ（mip 毎に縮む）
    uint outFaceSizeThisMip = max(1u, cubeSize >> mipLevel);
    // 1 texel の代表立体角
    float saTexel = texelSolidAngleApprox(outFaceSizeThisMip);

    // サンプル1つの代表立体角
    // 固定回数 N なら Nsample = params.sampleCount
    float saSample = 1.0f / (float(sampleCount) * pdfL + 1e-6f);

    // 必要 LOD を算出
    float mipL = mipFromSolidAngle(saSample, saTexel);

    // チューニング用の係数/バイアス（過度なボケを抑える）
    const float k    = 0.9f;   // 0.8〜1.1 で調整
    const float bias = 0.5f;   // 0.0〜0.5 で調整（残ノイズが辛い時に +）
    mipL = k * mipL + bias;

    // LOD をクランプ（envMap の最大 LOD に）
    mipL = clamp(mipL, 0.0f, envMaxMip);
    return mipL;
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
        // NOTE: jitterを入れることでhammersleyの規則性を崩す
        // en: Adding jitter breaks the regularity of hammersley
        float2 jitter = hash2(gid.x, gid.y, gid.z, params.mipLevel);
        xi = fract(xi + jitter);

        float  pdfH = 0.0f;
        float3 H    = sampleHalfVectorCharlie(xi, N, rSheen, &pdfH);
        float3 L    = normalize(reflect(-V, H));

        float NdotL = max(dot(N, L), 0.0f);
        if (NdotL <= 0.0f) continue;

        float VdotH = max(dot(V, H), 1e-5f);
        // H→L の pdf 変換： p(L) = p(H) / (4 * (V⋅H))
        float pdfL  = pdfH / (4.0f * VdotH);
        // モンテカルロ重み： NdotL / p(L)
        float w = NdotL / pdfL;

        // NOTE: mipLevelを制御した方が、ノイズが少なくなる.
        // en: to control mipLevel, it reduces noise.
        float mipL = optimizeMipLevel(pdfL,
                                      params.cubeSize,
                                      params.mipLevel,
                                      params.sampleCount,
                                      envMap.get_num_mip_levels() - 1);

        float3 Li = envMap.sample(s, L, level(mipL)).rgb;

        prefiltered += Li * w;
    }

    prefiltered = prefiltered / float(params.sampleCount);

    outMap.write(float4(prefiltered, 1.0), gid.xy, gid.z, params.mipLevel);
}
