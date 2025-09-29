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
                               float3 specularColor,
                               float3 sheenColor,
                               float sheenRoughness,
                               float clearcoatFactor,
                               float clearcoatRoughness,
                               float3 clearcoatNormal,
                               texture2d<float, access::sample> brdfLUT,
                               sampler brdfLUTSampler) {
    float3 N = normalize(normal);
    float3 V = normalize(viewPosition - worldPosition);
    float3 L = normalize(lightPosition - worldPosition);
    float3 H = normalize(V + L);
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    float3 F0 = compute_f0_rgb(ior, specularFactor, specularColor, albedo, metallic);

    float clearcoatWeight = saturate(clearcoatFactor);
    float baseAttenuation = 1.0 - clearcoatWeight;

    // Fresnel-Schlick approximation for the base layer
    float3 F = fresnelSchlick(max(dot(H, V), 0.0), F0);
    float3 F_base = F * baseAttenuation;

    // Geometry term (simplified Schlick-GGX)
    float G = geometrySmith(N, V, L, roughness);

    // Normal Distribution Function (GGX)
    float D = distributionGGX(N, H, roughness);

    // Specular term for the base layer
    float3 numerator = D * G * F_base;
    float denominator = 4.0 * NdotL * NdotV + 1e-4;
    float3 specular = numerator / denominator;

    // Diffuse term
    float3 diffuse = albedo / M_PI_F;

    // kS + kD = 1 (Energy conservation)
    float3 kS = F_base;
    float3 kD = (1.0 - kS) * (1.0 - metallic) * (1 - transmission);
    kD *= baseAttenuation;

    float3 baseLight = (kD * diffuse + specular) * ambientLightColor;

    // Sheen
    float FH = pow(1.0 - max(dot(L, H), 0.0), 5.0);
    float Vis_sheen = 1.0f / max(4.0 * dot(V, H) * dot(L, H), 1e-4);
    float D_sheen = D_Charlie(max(dot(N, H), 0.0), sheenRoughness);
    float3 F_sheen = sheenColor * FH;
    float3 sheenBRDF = F_sheen * D_sheen * Vis_sheen;
    float3 sheenLight = sheenBRDF * ambientLightColor;

    // Clearcoat (upper layer)
    float3 clearcoatContribution = float3(0.0);
    if (clearcoatWeight > 0.0) {
        float3 Nc = normalize(clearcoatNormal);
        float NdotLc = max(dot(Nc, L), 0.0);
        float NdotVc = max(dot(Nc, V), 0.0);
        if (NdotLc > 0.0 && NdotVc > 0.0) {
            float roughnessCoat = clamp(clearcoatRoughness, 0.001, 1.0);
            float Dc = distributionGGX(Nc, H, roughnessCoat);
            float Gc = geometrySmith(Nc, V, L, roughnessCoat);
            float Fc = fresnelSchlick(max(dot(H, V), 0.0), 0.04);
            float denomCoat = 4.0 * NdotLc * NdotVc + 1e-4;
            float specCoat = (Dc * Gc * Fc) / denomCoat;
            clearcoatContribution = clearcoatWeight * specCoat * ambientLightColor * NdotLc;
        }
    }

    // Energy conservation for sheen
    float sheenStrength = max(max(sheenColor.r, sheenColor.g), sheenColor.b);
    float E_sheen = brdfLUT.sample(brdfLUTSampler, float2(max(dot(N, V), 0.0), sheenRoughness)).b * sheenStrength;

    float3 result = (baseLight * (1 - E_sheen) + sheenLight) * NdotL;
    result += clearcoatContribution;

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
                                 float clearcoatFactor,
                                 float clearcoatRoughness,
                                 float3 clearcoatNormal,
                                 texturecube<float, access::sample> prefilterEnvMap,
                                 texturecube<float, access::sample> irradianceCubeMap,
                                 texture2d<float, access::sample> brdfLUT,
                                 float ior,
                                 float specularFactor,
                                 float3 specularColor,
                                 float3 sheenColor,
                                 float sheenRoughness,
                                 texturecube<float, access::sample> prefilterSheenMap) {
    constexpr sampler mipMapSampler(mag_filter::linear, min_filter::linear, mip_filter::linear, s_address::clamp_to_edge, t_address::clamp_to_edge);
    constexpr sampler texSampler(mag_filter::linear, min_filter::linear, s_address::clamp_to_edge, t_address::clamp_to_edge);

    float3 N = normalize(normal);
    float3 V = normalize(viewPosition - worldPosition);
    float3 R = reflect(-V, N);

    // Diffuse IBL
    float3 diffuse = irradianceCubeMap.sample(texSampler, N).rgb;

    // Fresnel-Schlick
    float3 F0_diel_rgb = compute_f0_dielectric_rgb(ior, specularFactor, specularColor);
    float clearcoatWeight = saturate(clearcoatFactor);
    float baseAttenuation = 1.0 - clearcoatWeight;
    float3 specularColorRGB = mix(F0_diel_rgb, albedo, metallic);
    float3 diffuseColor = albedo * (1.0 - metallic) * (1.0 - F0_diel_rgb) * (1.0 - transmission);

    // Specular IBL
    float textureSize = prefilterEnvMap.get_width();
    float maxMipLevel = floor(log2(textureSize));
    float mipLevel = roughness * maxMipLevel;
    float3 specular = prefilterEnvMap.sample(mipMapSampler, R, level(mipLevel)).rgb;

    // BRDF LUT
    float NdotV = max(dot(N, V), 0.0);
    float2 lut = brdfLUT.sample(texSampler, float2(NdotV, roughness)).rg;

    // Base light attenuated by clearcoat
    float3 baseDiffuse = diffuse * diffuseColor * baseAttenuation;
    float3 baseSpecular = specular * (specularColorRGB * lut.x + lut.y) * baseAttenuation;
    float3 baseLight = baseDiffuse + baseSpecular;

    // Sheen
    float2 sheenLUT = brdfLUT.sample(texSampler, float2(NdotV, sheenRoughness)).ba;
    float3 sheenIBL = prefilterSheenMap.sample(mipMapSampler, R, level(sheenRoughness * maxMipLevel)).rgb;
    float3 sheenLight = sheenIBL * sheenColor * sheenLUT.y;

    // Clearcoat IBL
    float3 clearcoatResult = float3(0.0);
    if (clearcoatWeight > 0.0) {
        float3 Nc = normalize(clearcoatNormal);
        float3 Rc = reflect(-V, Nc);
        float NdotVc = max(dot(Nc, V), 0.0);
        if (NdotVc > 0.0) {
            float roughnessCoat = clamp(clearcoatRoughness, 0.001, 1.0);
            float mipCoat = roughnessCoat * maxMipLevel;
            float3 clearcoatSpec = prefilterEnvMap.sample(mipMapSampler, Rc, level(mipCoat)).rgb;
            float2 lutCoat = brdfLUT.sample(texSampler, float2(NdotVc, roughnessCoat)).rg;
            float Fc = fresnelSchlick(NdotVc, 0.04);
            float clearcoatTerm = Fc * lutCoat.x + lutCoat.y;
            clearcoatResult = clearcoatWeight * clearcoatSpec * clearcoatTerm;
        }
    }

    // Energy conservation for sheen
    float sheenStrength = max(max(sheenColor.r, sheenColor.g), sheenColor.b);
    float E_sheen = sheenLUT.x * sheenStrength;

    float3 result = baseLight * (1 - E_sheen) + sheenLight;
    result += clearcoatResult;

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
