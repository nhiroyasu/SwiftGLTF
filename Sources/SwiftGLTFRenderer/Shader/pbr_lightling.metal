#include <metal_stdlib>
#include "includes/helper.h"
#include "includes/pbr_lighting.h"
#include "includes/pbr_fresnel.h"

using namespace metal;

float3 compute_direct_lighting(float3 normal,
                               float3 worldPosition,
                               float3 albedo,
                               float metallic,
                               float roughness,
                               float transmission,
                               float3 viewPosition,
                               float3 lightPosition,
                               float3 ambientLightColor,
                               float ior,
                               float specularFactor,
                               float3 specularColor) {
    float3 N = normalize(normal);
    float3 V = normalize(viewPosition - worldPosition);
    float3 L = normalize(lightPosition - worldPosition);
    float3 H = normalize(V + L);
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    float3 F0 = compute_f0_rgb(ior, specularFactor, specularColor, albedo, metallic);

    // Fresnel-Schlick approximation
    float3 F = fresnelSchlick(max(dot(H, V), 0.0), F0);

    // Geometry term (simplified Schlick-GGX)
    float G = geometrySmith(N, V, L, roughness);

    // Normal Distribution Function (GGX)
    float D = distributionGGX(N, H, roughness);

    float3 numerator = D * G * F;
    float denominator = 4.0 * NdotL * NdotV + 1e-4;
    float3 specular = numerator / denominator;

    // kS + kD = 1 (Energy conservation)
    float3 kS = F;
    float3 kD = (1.0 - kS) * (1.0 - metallic) * (1 - transmission);
    float3 diffuse = albedo / M_PI_F;

    float3 radiance = ambientLightColor;
    float3 result = (kD * diffuse + specular) * radiance * NdotL;

    return result;
}

float3 compute_indirect_lighting(float3 normal,
                                 float3 worldPosition,
                                 float3 viewPosition,
                                 float3 albedo,
                                 float metallic,
                                 float roughness,
                                 float ambientOcclusion,
                                 float transmission,
                                 texturecube<float, access::sample> prefilterEnvMap,
                                 texturecube<float, access::sample> irradianceCubeMap,
                                 texture2d<float, access::sample> brdfLUT,
                                 float ior,
                                 float specularFactor,
                                 float3 specularColor) {
    constexpr sampler mipMapSampler(mag_filter::linear, min_filter::linear, mip_filter::linear, s_address::clamp_to_edge, t_address::clamp_to_edge);
    constexpr sampler texSampler(mag_filter::linear, min_filter::linear, s_address::clamp_to_edge, t_address::clamp_to_edge);

    float3 N = normalize(normal);
    float3 V = normalize(viewPosition - worldPosition);
    float3 R = reflect(-V, N);

    // Diffuse IBL
    float3 diffuse = irradianceCubeMap.sample(texSampler, N).rgb;

    // Fresnel-Schlick
    float3 F0_diel_rgb = compute_f0_dielectric_rgb(ior, specularFactor, specularColor);
    float3 specularColorRGB = mix(F0_diel_rgb, albedo, metallic);
    float3 diffuseColor = albedo * (1.0 - metallic) * (1.0 - F0_diel_rgb) * (1.0 - transmission);

    // Specular IBL
    float textureSize = prefilterEnvMap.get_width();
    float maxMipLevel = floor(log2(textureSize));
    float mipLevel = roughness * maxMipLevel;
    float3 specular = prefilterEnvMap.sample(mipMapSampler, R, level(mipLevel)).rgb;

    // BRDF LUT
    float2 lut = brdfLUT.sample(texSampler, float2(max(dot(N, V), 0.0), roughness)).rg;

    // result
    float3 result = diffuse * diffuseColor + specular * (specularColorRGB * lut.x + lut.y);

    // Apply ambient occlusion
    result *= ambientOcclusion;

    return result;
}

float3 compute_transmission_lighting(float3 Lbg,
                                     float3 normal,
                                     float3 albedo,
                                     float metallic,
                                     float transmission,
                                     float3 attenuation,
                                     float3 worldPosition,
                                     float3 viewPosition,
                                     float ior,
                                     float specularFactor,
                                     float3 specularColor) {
    float3 N = normalize(normal);
    float3 V = normalize(viewPosition - worldPosition);

    float3 F0_diel_rgb = compute_f0_dielectric_rgb(ior, specularFactor, specularColor);
    float F = fresnelSchlick(max(dot(N, V), 0.0), max(max(F0_diel_rgb.r, F0_diel_rgb.g), F0_diel_rgb.b));

    float kTrans = saturate(transmission * (1.0 - metallic) * (1.0 - F));
    float3 refractedColor = Lbg * attenuation * albedo * kTrans;
    return refractedColor;
}
