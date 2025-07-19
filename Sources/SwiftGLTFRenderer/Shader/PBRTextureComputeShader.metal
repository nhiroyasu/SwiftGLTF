#include <metal_stdlib>
#include "headers/pbr.h"
#include "headers/metal_helper.h"
using namespace metal;

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

kernel void prefilterLambertEnvMap(texturecube<float, access::sample> envMap [[texture(0)]],
                                   texturecube<float, access::write> diffuseEnvMap [[texture(1)]],
                                   uint3 gid [[thread_position_in_grid]])
{
    sampler sampler(mag_filter::linear, min_filter::linear, mip_filter::linear);

    uint width = diffuseEnvMap.get_width();
    uint height = diffuseEnvMap.get_height();
    float u = float(gid.x) / float(width - 1);
    float v = float(gid.y) / float(height - 1);

    float3 lambertColor = float3(0.0);
    const uint sampleCount = 1024;
    float x;
    float y;
    float z;
    switch (gid.z) {
        case 0: // positive x
            x = 0.5;
            y = 0.5 - v;
            z = 0.5 - u;
            break;
        case 1: // negative x
            x = -0.5;
            y = 0.5 - v;
            z = u - 0.5;
            break;
        case 2: // positive y
            x = u - 0.5;
            y = 0.5;
            z = v - 0.5;
            break;
        case 3: // negative y
            x = u - 0.5;
            y = -0.5;
            z = 0.5 - v;
            break;
        case 4: // positive z
            x = u - 0.5;
            y = 0.5 - v;
            z = 0.5;
            break;
        case 5: // negative z
            x = 0.5 - u;
            y = 0.5 - v;
            z = -0.5;
            break;
        default:
            assert(false);
            x = 0;
            y = 0;
            z = 0;
            break;
    }

    float3 N = normalize(float3(x, y, z));

    for (uint i = 0; i < sampleCount; i++) {
        float2 xi = hammersley(i, sampleCount);
        float3 H = ImportanceSampleCosineWeighted(xi, N);
        lambertColor += ACESFilm(envMap.sample(sampler, H, level(0)).rgb);
    }
    lambertColor /= float(sampleCount);
    diffuseEnvMap.write(float4(lambertColor, 1.0), gid.xy, gid.z);
}
