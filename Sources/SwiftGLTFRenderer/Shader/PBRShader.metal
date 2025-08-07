#include <metal_stdlib>
#include "../../SwiftGLTFShaderTypes/includes/pbr.h"
#include "includes/metal_helper.h"
using namespace metal;

// MARK: - Compute lighting

float3 compute_direct_lighting(float3 normal,
                               float3 worldPosition,
                               float3 albedo,
                               float metallic,
                               float roughness,
                               float3 viewPosition,
                               float3 lightPosition,
                               float3 ambientLightColor) {
    float3 N = normalize(normal);
    float3 V = normalize(viewPosition - worldPosition);
    float3 L = normalize(lightPosition - worldPosition);
    float3 H = normalize(V + L);
    float3 F0 = mix(float3(0.04), albedo, metallic);

    // Fresnel-Schlick approximation
    float3 F = F0 + (1.0 - F0) * pow(clamp(1.0 - dot(H, V), 0.0, 1.0), 5.0);

    // Geometry term (simplified Schlick-GGX)
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    float roughness2 = roughness * roughness;
    float k = (roughness + 1.0) * (roughness + 1.0) / 8.0;
    float G_V = NdotV / (NdotV * (1.0 - k) + k);
    float G_L = NdotL / (NdotL * (1.0 - k) + k);
    float G = G_V * G_L;

    // Normal Distribution Function (GGX)
    float NdotH = max(dot(N, H), 0.0);
    float alpha = roughness2;
    float alpha2 = alpha * alpha;
    float denom = NdotH * NdotH * (alpha2 - 1.0) + 1.0;
    float D = alpha2 / (M_PI_F * denom * denom + 1e-4);

    float3 numerator = D * G * F;
    float denominator = 4.0 * NdotL * NdotV + 1e-4;
    float3 specular = numerator / denominator;

    // kS + kD = 1 (Energy conservation)
    float3 kS = F;
    float3 kD = (1.0 - kS) * (1.0 - metallic);
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
                                 texturecube<float, access::sample> prefilterEnvMap,
                                 texturecube<float, access::sample> irradianceCubeMap,
                                 texture2d<float, access::sample> brdfLUT) {
    constexpr sampler mipMapSampler(mag_filter::linear, min_filter::linear, mip_filter::linear, s_address::clamp_to_edge, t_address::clamp_to_edge);
    constexpr sampler texSampler(mag_filter::linear, min_filter::linear, s_address::clamp_to_edge, t_address::clamp_to_edge);

    float3 N = normalize(normal);
    float3 V = normalize(viewPosition - worldPosition);
    float3 R = reflect(-V, N);

    // Diffuse IBL
    float3 diffuse = irradianceCubeMap.sample(texSampler, N).rgb;

    // Fresnel-Schlick
    float3 f0 = float3(0.04);
    float3 specularColor = mix(f0, albedo, metallic);
    float3 diffuseColor = albedo * (1.0 - f0);
    diffuseColor *= 1.0 - metallic;

    // Specular IBL
    float textureSize = prefilterEnvMap.get_width();
    float maxMipLevel = floor(log2(textureSize));
    float mipLevel = roughness * maxMipLevel;
    float3 specular = prefilterEnvMap.sample(mipMapSampler, R, level(mipLevel)).rgb;

    // BRDF LUT
    float2 brdf = brdfLUT.sample(texSampler, float2(max(dot(N, V), 0.0), roughness)).rg;


    // result
    float3 result = diffuse * diffuseColor + specular * (specularColor * brdf.x + brdf.y);

    // Apply ambient occlusion
    result *= ambientOcclusion;

    return result;
}

// MARK: - Shader Structures

struct VertexIn {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float4 tangent [[attribute(2)]];
    float2 uv [[attribute(3)]];
    float4 modulationColor [[attribute(4)]];
};

struct PBRVertexOut {
    float4 position [[position]];
    float3 worldPosition;
    float3 normal;
    float4 tangent;
    float2 uv;
    float4 modulationColor;
};

struct PBRFragmentArguments {
    constant PBRMaterialUniforms &material [[id(0)]];
    bool hasBaseColorTexture [[id(1)]];
    texture2d<float> baseColorTexture [[id(2)]];
    sampler baseColorSampler [[id(3)]];
    bool hasNormalTexture [[id(4)]];
    texture2d<float> normalTexture [[id(5)]];
    sampler normalSampler [[id(6)]];
    bool hasMetallicRoughnessTexture [[id(7)]];
    texture2d<float> metallicRoughnessTexture [[id(8)]];
    sampler metallicRoughnessSampler [[id(9)]];
    bool hasEmissiveTexture [[id(10)]];
    texture2d<float> emissiveTexture [[id(11)]];
    sampler emissiveSampler [[id(12)]];
    bool hasOcclusionTexture [[id(13)]];
    texture2d<float> occlusionTexture [[id(14)]];
    sampler occlusionSampler [[id(15)]];
};

struct PBREnvMapArguments {
    texturecube<float> prefilterEnvMap [[id(0)]];
    texturecube<float> irradianceMap [[id(1)]];
    texture2d<float> brdfLUT [[id(2)]];
};

// MARK: - PBR Shader

vertex PBRVertexOut pbr_vertex_shader(VertexIn in [[stage_in]],
                                      constant float4x4 &model [[buffer(1)]],
                                      constant PBRVertexVariableParameters &params [[buffer(2)]])
{
    PBRVertexOut out;

    float4x4 modelTransform = params.externalTransform * model;
    float4x4 mvpTransform = params.projection * params.view * modelTransform;

    float3x3 normalTransform = transpose(inverse(_float3x3(modelTransform)));

    out.position = mvpTransform * float4(in.position, 1.0);
    out.worldPosition = (modelTransform * float4(in.position, 1.0)).xyz;
    out.normal = normalize(normalTransform * in.normal);
    out.tangent = normalize(float4(normalTransform * in.tangent.xyz, in.tangent.w));
    out.uv = in.uv;
    out.modulationColor = in.modulationColor;
    return out;
}

fragment float4 pbr_fragment_shader(PBRVertexOut in [[stage_in]],
                                    constant PBRFragmentArguments &fragArgs [[buffer(0)]],
                                    constant PBREnvMapArguments &envMapArgs [[buffer(1)]],
                                    constant PBRFragmentVariableParameters &params [[buffer(2)]])
{
    constant PBRMaterialUniforms &mUni = fragArgs.material;
    texture2d<float> baseColorTexture = fragArgs.baseColorTexture;
    sampler baseColorSampler = fragArgs.baseColorSampler;
    texture2d<float> normalTexture = fragArgs.normalTexture;
    sampler normalSampler = fragArgs.normalSampler;
    texture2d<float> metallicRoughnessTexture = fragArgs.metallicRoughnessTexture;
    sampler metallicRoughnessSampler = fragArgs.metallicRoughnessSampler;
    texture2d<float> emissiveTexture = fragArgs.emissiveTexture;
    sampler emissiveSampler = fragArgs.emissiveSampler;
    texture2d<float> occlusionTexture = fragArgs.occlusionTexture;
    sampler occlusionSampler = fragArgs.occlusionSampler;

    texturecube<float> prefilterEnvMap = envMapArgs.prefilterEnvMap;
    texturecube<float> irradianceMap = envMapArgs.irradianceMap;
    texture2d<float> brdfLUT = envMapArgs.brdfLUT;

    float2 uv = in.uv;
    float4 modulationColor = in.modulationColor;

    // Apply base color texture, vertex modulation color, and material base color factor
    float3 albedo = fragArgs.hasBaseColorTexture
    ? baseColorTexture.sample(baseColorSampler, uv).rgb * modulationColor.rgb * mUni.baseColorFactor.rgb
    : float3(1, 1, 1) * modulationColor.rgb * mUni.baseColorFactor.rgb;

    // Sample metallic-roughness and occlusion, apply material factors
    float metallic = fragArgs.hasMetallicRoughnessTexture
    ? metallicRoughnessTexture.sample(metallicRoughnessSampler, uv).b * mUni.metalRoughnessOcclusion.x
    : 1.0 * mUni.metalRoughnessOcclusion.x;
    float roughness = fragArgs.hasMetallicRoughnessTexture
    ? metallicRoughnessTexture.sample(metallicRoughnessSampler, uv).g * mUni.metalRoughnessOcclusion.y
    : 1.0 * mUni.metalRoughnessOcclusion.y;

    // Emissive lighting: apply material emissive factor
    float3 emissive = fragArgs.hasEmissiveTexture
    ? emissiveTexture.sample(emissiveSampler, uv).rgb * mUni.emissiveFactor.rgb
    : float3(1, 1, 1) * mUni.emissiveFactor.rgb;

    // Ambient occlusion: apply material occlusion factor
    float ambientOcclusion = fragArgs.hasOcclusionTexture
    ? occlusionTexture.sample(occlusionSampler, uv).r * mUni.metalRoughnessOcclusion.z
    : 1.0 * mUni.metalRoughnessOcclusion.z;

    float3 N = normalize(in.normal);
    float3x3 TBN = make_tbn(N, in.tangent.xyz, in.tangent.w);

    float3 normalTexValue = fragArgs.hasNormalTexture
    ? normalTexture.sample(normalSampler, uv).rgb * 2.0 - 1.0
    : float3(0, 0, 1);
    float3 normal = normalize(TBN * normalTexValue);

    float3 worldPosition = in.worldPosition;
    float3 viewPosition = params.viewPosition;

    // Direct lighting
    float3 directLighting = compute_direct_lighting(normal,
                                                    worldPosition,
                                                    albedo,
                                                    metallic,
                                                    roughness,
                                                    params.viewPosition,
                                                    params.lightPosition,
                                                    params.ambientLightColor);

    // Indirect lighting
    float3 indirectLighting = compute_indirect_lighting(normal,
                                                        worldPosition,
                                                        viewPosition,
                                                        albedo,
                                                        metallic,
                                                        roughness,
                                                        ambientOcclusion,
                                                        prefilterEnvMap,
                                                        irradianceMap,
                                                        brdfLUT);

    // Final color
    float3 color = directLighting + indirectLighting + emissive;

    return float4(color, 1.0);
}
