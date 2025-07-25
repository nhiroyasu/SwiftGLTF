#include <metal_stdlib>
#include "../../SwiftGLTFShaderTypes/includes/pbr.h"
#include "../../SwiftGLTFShaderTypes/includes/metal_helper.h"
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
                                 texturecube<float, access::sample> specularCubeMap,
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
    float textureSize = specularCubeMap.get_width();
    float maxMipLevel = floor(log2(textureSize));
    float mipLevel = roughness * maxMipLevel;
    float3 specular = specularCubeMap.sample(mipMapSampler, R, level(mipLevel)).rgb;

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

// MARK: - PBR Shader

vertex PBRVertexOut pbr_vertex_shader(VertexIn in [[stage_in]],
                                      constant float4x4 &model [[buffer(1)]],
                                      constant float4x4 &view [[buffer(2)]],
                                      constant float4x4 &projection [[buffer(3)]],
                                      constant float4x4 &externalTransform [[buffer(4)]]) {
    PBRVertexOut out;

    float4x4 modelTransform = model * externalTransform;
    float4x4 mvpTransform = projection * view * modelTransform;

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
                                    constant PBRVertexUniforms &vUni [[buffer(0)]],
                                    constant PBRSceneUniforms &sUni [[buffer(1)]],
                                    texturecube<float, access::sample> specularCubeMap [[ texture(0) ]],
                                    texturecube<float, access::sample> irradianceMap [[ texture(1) ]],
                                    texture2d<float, access::sample> brdfLUT [[ texture(2) ]],
                                    texture2d<float, access::sample> baseColorTexture [[ texture(3) ]],
                                    sampler baseColorSampler [[ sampler(0) ]],
                                    texture2d<float, access::sample> normalTexture [[ texture(4) ]],
                                    sampler normalSampler [[ sampler(1) ]],
                                    texture2d<float, access::sample> metallicRoughnessTexture [[ texture(5) ]],
                                    sampler metallicRoughnessSampler [[ sampler(2) ]],
                                    texture2d<float, access::sample> emissiveTexture [[ texture(6) ]],
                                    sampler emissiveSampler [[ sampler(3) ]],
                                    texture2d<float, access::sample> occlusionTexture [[ texture(7) ]],
                                    sampler occlusionSampler [[ sampler(4) ]]) {
    float2 uv = vUni.hasUV ? in.uv : float2(0.0, 0.0);
    float4 modulationColor = vUni.hasModulationColor ? in.modulationColor : float4(1.0, 1.0, 1.0, 1.0);

    float3 albedo = baseColorTexture.sample(baseColorSampler, uv).rgb * modulationColor.rgb;
    float metallic = metallicRoughnessTexture.sample(metallicRoughnessSampler, uv).b;
    float roughness = metallicRoughnessTexture.sample(metallicRoughnessSampler, uv).g;
    float ambientOcclusion = occlusionTexture.sample(occlusionSampler, uv).r;

    float3 N = normalize(in.normal);
    float3x3 TBN = vUni.hasTangent ? make_tbn(N, in.tangent.xyz, in.tangent.w) : make_tbn(N);

    float3 normalTexValue = normalTexture.sample(normalSampler, uv).rgb * 2.0 - 1.0;
    float3 normal = normalize(TBN * normalTexValue);

    float3 worldPosition = in.worldPosition;
    float3 viewPosition = sUni.viewPosition;

    // Direct lighting
    float3 directLighting = compute_direct_lighting(normal,
                                                    worldPosition,
                                                    albedo,
                                                    metallic,
                                                    roughness,
                                                    sUni.viewPosition,
                                                    sUni.lightPosition,
                                                    sUni.ambientLightColor);

    // Indirect lighting
    float3 indirectLighting = compute_indirect_lighting(normal,
                                                        worldPosition,
                                                        viewPosition,
                                                        albedo,
                                                        metallic,
                                                        roughness,
                                                        ambientOcclusion,
                                                        specularCubeMap,
                                                        irradianceMap,
                                                        brdfLUT);

    // Emissive lighting
    float3 emissive = emissiveTexture.sample(emissiveSampler, uv).rgb;

    // Final color
    float3 color = directLighting + indirectLighting + emissive;

    return float4(color, 1.0);
}

// MARK: - Debug Shader

fragment float4 normal_display_shader(PBRVertexOut in [[stage_in]],
                                      constant PBRVertexUniforms &vUni [[buffer(0)]],
                                      texture2d<float, access::sample> normalTexture [[ texture(4) ]],
                                      sampler normalSampler [[ sampler(1) ]]) {
    float2 uv = vUni.hasUV ? in.uv : float2(0.0, 0.0);

    float3 N = normalize(in.normal);
    float3x3 TBN = vUni.hasTangent ? make_tbn(N, in.tangent.xyz, in.tangent.w) : make_tbn(N);

    float3 normalTexValue = normalTexture.sample(normalSampler, uv).rgb * 2.0 - 1.0;
    float3 normal = normalize(TBN * normalTexValue);
    // -1 ~ 1 → 0 ~ 1
    normal = (normal + 1.0) * 0.5;

    return float4(normal, 1.0); // Display normal as RGB
}

fragment float4 tangent_display_shader(PBRVertexOut in [[stage_in]],
                                      constant PBRVertexUniforms &vUni [[buffer(0)]]) {

    float3 tangent = vUni.hasTangent ? in.tangent.xyz : float3(0.0, 0.0, 0.0);
    tangent = normalize(tangent);
    // -1 ~ 1 → 0 ~ 1
    tangent = (tangent + 1.0) * 0.5;

    return float4(tangent, 1.0); // Display tangent as RGB
}
