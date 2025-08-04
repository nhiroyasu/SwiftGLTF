#include <metal_stdlib>
#include "../../SwiftGLTFShaderTypes/includes/pbr.h"
#include "includes/metal_helper.h"
using namespace metal;

float3 getDirectionForFace(uint faceIndex, float2 uv) {
    switch (faceIndex) {
        case 0: return normalize(float3(1.0, -uv.y, -uv.x)); // +X
        case 1: return normalize(float3(-1.0, -uv.y, uv.x)); // -X
        case 2: return normalize(float3(uv.x, 1.0, uv.y));    // +Y
        case 3: return normalize(float3(uv.x, -1.0, -uv.y));  // -Y
        case 4: return normalize(float3(uv.x, -uv.y, 1.0));   // +Z
        case 5: return normalize(float3(-uv.x, -uv.y, -1.0)); // -Z
        default: return float3(0.0);
    }
}

kernel void generateBRDFLUT(texture2d<float, access::write> brdfLUT [[texture(0)]],
                            uint2 gid [[thread_position_in_grid]])
{
    uint width = brdfLUT.get_width();
    uint height = brdfLUT.get_height();

    if (gid.x >= width || gid.y >= height) {
        return;
    }

    float x = float(gid.x) / float(width - 1);
    float y = float(gid.y) / float(height - 1);

    float roughness = y;
    float NdotV = max(x, 1e-4);

    float3 V = float3(sqrt(1.0 - NdotV * NdotV), 0.0, NdotV);
    float3 N = float3(0.0, 0.0, 1.0);

    float A = 0.0;
    float B = 0.0;

    // フレネル項と幾何減衰項の計算
    // en: Calculation of Fresnel terms and geometric attenuation terms
    const int SAMPLE_COUNT = 1024;
    for (int i = 0; i < SAMPLE_COUNT; i++) {
        float2 xi = hammersley(i, SAMPLE_COUNT);
        float3 H = importanceSampleGGX(xi, N, roughness);
        float3 L = normalize(2.0 * dot(V, H) * H - V);

        float NdotL = max(L.z, 0.0);
        float NdotH = max(H.z, 0.0);
        float VdotH = max(dot(V, H), 0.0);

        if (NdotL > 0.0) {
            float G = geometrySmith(NdotV, NdotL, roughness);
            float G_Vis = (G * VdotH) / (NdotH * NdotV);
            float Fc = pow(1.0 - VdotH, 5.0);
            A += (1.0 - Fc) * G_Vis;
            B += Fc * G_Vis;
        }
    }

    A /= float(SAMPLE_COUNT);
    B /= float(SAMPLE_COUNT);

    brdfLUT.write(float4(A, B, 0.0, 1.0), gid);
}

kernel void irradianceMap(texturecube<float, access::sample> envMap [[texture(0)]],
                                   texturecube<float, access::write> out [[texture(1)]],
                                   constant IrradianceMapParams &params [[buffer(0)]],
                                   uint3 gid [[thread_position_in_grid]])
{
    uint size = params.cubeSize;

    if (gid.x >= size || gid.y >= size) return;

    float2 uv = (float2(gid.xy) + 0.5) / float(size) * 2.0 - 1.0; // Convert to [-1, 1] range
    float3 N = normalize(getDirectionForFace(gid.z, uv));

    constexpr sampler sampler(mip_filter::linear);

    float3x3 tbn = make_tbn(N);
    float3 irradiance = float3(0.0);
    uint sampleCount = 0;

    float delta = 0.025;
    for (float phi = 0.0; phi < M_PI_F * 2.0; phi += delta) {
        for (float theta = 0.0; theta < M_PI_F * 0.5; theta += delta) {
            float3 tangentSample = float3(sin(theta) * cos(phi),
                                          sin(theta) * sin(phi),
                                          cos(theta));

            float3 sampleVec = normalize(tbn[0] * tangentSample.x +
                                         tbn[1] * tangentSample.y +
                                         tbn[2] * tangentSample.z);

            float weight = cos(theta) * sin(theta);
            irradiance += envMap.sample(sampler, sampleVec).rgb * weight;
            sampleCount++;
        }
    }

    irradiance = M_PI_F * irradiance / float(sampleCount);

    out.write(float4(irradiance, 1.0), gid.xy, gid.z);
}

kernel void prefilterEnvMap(texturecube<float, access::sample> envMap [[texture(0)]],
                            texturecube<float, access::write> outMap [[texture(1)]],
                            constant PreFilterEnvMapParams &params [[buffer(0)]],
                            uint3 gid [[thread_position_in_grid]])
{
    if (gid.x >= params.cubeSize || gid.y >= params.cubeSize) return;

    float2 uv = (float2(gid.xy) + 0.5) / float(params.cubeSize) * 2.0 - 1.0; // Convert to [-1, 1] range
    float3 R = getDirectionForFace(gid.z, uv);
    float3 N = normalize(R);
    float3 V = N;

    constexpr sampler sampler(mip_filter::linear);

    float3 prefilteredColor = float3(0.0);
    float totalWeight = 0.0;

    for (uint i = 0; i < params.sampleCount; ++i) {
        float2 xi = hammersley(i, params.sampleCount);
        float3 H = importanceSampleGGX(xi, N, params.roughness);
        float3 L = normalize(2.0 * dot(V, H) * H - V);

        float NdotL = max(dot(N, L), 0.0);
        if (NdotL > 0.0) {
            prefilteredColor += envMap.sample(sampler, L).rgb * NdotL;
            totalWeight += NdotL;
        }
    }

    prefilteredColor = totalWeight > 0.0 ? prefilteredColor / totalWeight : float3(0.0);

    outMap.write(float4(prefilteredColor, 1.0), gid.xy, gid.z, params.mipLevel);
}
