#include <metal_stdlib>
#include "headers/pbr.h"
#include "headers/metal_helper.h"
using namespace metal;

// MARK: - Compute lighting

float3 compute_ambient(float3 albedo) {
    // Ambient lighting contribution
    float3 ambientColor = float3(0.03) * albedo; // Simple ambient term
    return ambientColor;
}

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

float3x3 make_tbn(float3 normal) {
    // Construct a TBN matrix assuming the normal is Z and use a fixed tangent space
    float3 up = abs(normal.y) < 0.999 ? float3(0, 1, 0) : float3(1, 0, 0);
    float3 tangent = normalize(cross(up, normal));
    float3 bitangent = cross(normal, tangent);
    return float3x3(tangent, bitangent, normal);
}

float3x3 make_tbn(float3 N, float3 T, float Tw) {
    float3 B = cross(N, T) * Tw;
    return float3x3(T, B, N);
}

// MARK: - Shaders for PNU(Position, Normal, UV)

struct VertexIn_PNU {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float2 uv [[attribute(3)]];
};

struct VertexOut_PNU {
    float4 position [[position]];
    float3 worldPosition;
    float3 normal;
    float2 uv;
};

vertex VertexOut_PNU pbr_pnu_vertex_shader(VertexIn_PNU in [[stage_in]],
                                   constant float4x4 &model [[buffer(1)]],
                                   constant float4x4 &view [[buffer(2)]],
                                   constant float4x4 &projection [[buffer(3)]],
                                   constant float3x3 &normalMatrix [[buffer(4)]]) {
    VertexOut_PNU out;

    float4x4 mvpMatrix = projection * view * model;

    out.position = mvpMatrix * float4(in.position, 1.0);
    out.worldPosition = (model * float4(in.position, 1.0)).xyz;
    out.normal = normalize(normalMatrix * in.normal);
    out.uv = in.uv;
    return out;
}

fragment float4 pbr_pnu_fragment_shader(VertexOut_PNU in [[stage_in]],
                                        constant PBRSceneUniforms &uniforms [[buffer(0)]],
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

    float3 albedo = baseColorTexture.sample(baseColorSampler, in.uv).rgb;
    float metallic = metallicRoughnessTexture.sample(metallicRoughnessSampler, in.uv).b;
    float roughness = metallicRoughnessTexture.sample(metallicRoughnessSampler, in.uv).g;
    float ambientOcclusion = occlusionTexture.sample(occlusionSampler, in.uv).r;

    // Default normal from vertex normal
    float3 normal = normalize(in.normal);
    if (normalTexture.get_width() > 0 && normalTexture.get_height() > 0) {
        float3 normalSample = normalTexture.sample(normalSampler, in.uv).rgb;
        float3 tangentNormal = normalSample * 2.0 - 1.0;

        // Construct a TBN matrix assuming the normal is Z and use a fixed tangent space
        float3x3 tbn = make_tbn(normal);

        normal = normalize(tbn * tangentNormal);
    }
    float3 worldPosition = in.worldPosition;
    float3 viewPosition = uniforms.viewPosition;

    // Direct lighting
    float3 directLighting = compute_direct_lighting(normal,
                                                    worldPosition,
                                                    albedo,
                                                    metallic,
                                                    roughness,
                                                    uniforms.viewPosition,
                                                    uniforms.lightPosition,
                                                    uniforms.ambientLightColor);

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
    float3 emissive = emissiveTexture.sample(emissiveSampler, in.uv).rgb;

    // Final color
    float3 color = directLighting + indirectLighting + emissive;

    return float4(color, 1.0);
};

// MARK: - Shader for PN(Position, Normal)

struct VertexIn_PN {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
};

struct VertexOut_PN {
    float4 position [[position]];
    float3 worldPosition;
    float3 normal;
};

vertex VertexOut_PN pbr_pn_vertex_shader(VertexIn_PN in [[stage_in]],
                                         constant float4x4 &model [[buffer(1)]],
                                         constant float4x4 &view [[buffer(2)]],
                                         constant float4x4 &projection [[buffer(3)]],
                                         constant float3x3 &normalMatrix [[buffer(4)]]) {
    VertexOut_PN out;

    float4x4 mvpMatrix = projection * view * model;

    out.position = mvpMatrix * float4(in.position, 1.0);
    out.worldPosition = (model * float4(in.position, 1.0)).xyz;
    out.normal = normalize(normalMatrix * in.normal);
    return out;
}

fragment float4 pbr_pn_fragment_shader(VertexOut_PN in [[stage_in]],
                                       constant PBRSceneUniforms &uniforms [[buffer(0)]],
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

    // Default albedo from material
    float2 uv = float2(0, 0);
    float3 albedo = baseColorTexture.sample(baseColorSampler, uv).rgb;
    float metallic = metallicRoughnessTexture.sample(metallicRoughnessSampler, uv).b;
    float roughness = metallicRoughnessTexture.sample(metallicRoughnessSampler, uv).g;
    float ambientOcclusion = occlusionTexture.sample(occlusionSampler, uv).r;

    float3 normal = normalize(in.normal);
    float3 worldPosition = in.worldPosition;
    float3 viewPosition = uniforms.viewPosition;

    // Direct lighting
    float3 directLighting = compute_direct_lighting(normal,
                                                    worldPosition,
                                                    albedo,
                                                    metallic,
                                                    roughness,
                                                    uniforms.viewPosition,
                                                    uniforms.lightPosition,
                                                    uniforms.ambientLightColor);

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
};

// MARK: -Shader for PU(Position, UV)

struct VertexIn_PU {
    float3 position [[attribute(0)]];
    float2 uv [[attribute(3)]];
};

struct VertexOut_PU {
    float4 position [[position]];
    float3 worldPosition;
    float2 uv;
};

vertex VertexOut_PU pbr_pu_vertex_shader(VertexIn_PU in [[stage_in]],
                                         constant float4x4 &model [[buffer(1)]],
                                         constant float4x4 &view [[buffer(2)]],
                                         constant float4x4 &projection [[buffer(3)]]) {
    VertexOut_PU out;

    float4x4 mvpMatrix = projection * view * model;

    out.position = mvpMatrix * float4(in.position, 1.0);
    out.worldPosition = (model * float4(in.position, 1.0)).xyz;
    out.uv = in.uv;
    return out;
}

fragment float4 pbr_pu_fragment_shader(VertexOut_PU in [[stage_in]],
                                       constant PBRSceneUniforms &uniforms [[buffer(0)]],
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

    float3 albedo = baseColorTexture.sample(baseColorSampler, in.uv).rgb;
    float metallic = metallicRoughnessTexture.sample(metallicRoughnessSampler, in.uv).b;
    float roughness = metallicRoughnessTexture.sample(metallicRoughnessSampler, in.uv).g;
    float ambientOcclusion = occlusionTexture.sample(occlusionSampler, in.uv).r;

    float3 normal = normalize(uniforms.viewPosition); // Default normal for view position
    float3 worldPosition = in.worldPosition;
    float3 viewPosition = uniforms.viewPosition;

    // Direct lighting
    float3 directLighting = compute_direct_lighting(normal,
                                                    worldPosition,
                                                    albedo,
                                                    metallic,
                                                    roughness,
                                                    uniforms.viewPosition,
                                                    uniforms.lightPosition,
                                                    uniforms.ambientLightColor);

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
    float3 emissive = emissiveTexture.sample(emissiveSampler, float2(0, 0)).rgb;

    // Final color
    float3 color = directLighting + indirectLighting + emissive;

    return float4(color, 1.0);
};

// MARK: - Shader for P(Position)

struct VertexIn_P {
    float3 position [[attribute(0)]];
};

struct VertexOut_P {
    float4 position [[position]];
    float3 worldPosition;
};

vertex VertexOut_P pbr_p_vertex_shader(VertexIn_P in [[stage_in]],
                                       constant float4x4 &model [[buffer(1)]],
                                       constant float4x4 &view [[buffer(2)]],
                                       constant float4x4 &projection [[buffer(3)]]) {
    VertexOut_P out;

    float4x4 mvpMatrix = projection * view * model;

    out.position = mvpMatrix * float4(in.position, 1.0);
    out.worldPosition = (model * float4(in.position, 1.0)).xyz;
    return out;
}

fragment float4 pbr_p_fragment_shader(VertexOut_P in [[stage_in]],
                                      constant PBRSceneUniforms &uniforms [[buffer(0)]],
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

    float2 uv = float2(0, 0); // Default UV coordinates
    float3 albedo = baseColorTexture.sample(baseColorSampler, uv).rgb;
    float metallic = metallicRoughnessTexture.sample(metallicRoughnessSampler, uv).b;
    float roughness = metallicRoughnessTexture.sample(metallicRoughnessSampler, uv).g;
    float ambientOcclusion = occlusionTexture.sample(occlusionSampler, uv).r;

    float3 normal = normalize(uniforms.viewPosition); // Default normal for view position
    float3 worldPosition = in.worldPosition;
    float3 viewPosition = uniforms.viewPosition;

    // Direct lighting
    float3 directLighting = compute_direct_lighting(normal,
                                                    worldPosition,
                                                    albedo,
                                                    metallic,
                                                    roughness,
                                                    uniforms.viewPosition,
                                                    uniforms.lightPosition,
                                                    uniforms.ambientLightColor);

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
    float3 emissive = emissiveTexture.sample(emissiveSampler, float2(0, 0)).rgb;

    // Final color
    float3 color = directLighting + indirectLighting + emissive;

    return float4(color, 1.0);
};

// MARK: - Shaders for PNUC(Position, Normal, UV, Modulation-Color)

struct VertexIn_PNUC {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float2 uv [[attribute(3)]];
    float4 modulationColor [[attribute(4)]];
};

struct VertexOut_PNUC {
    float4 position [[position]];
    float3 worldPosition;
    float3 normal;
    float2 uv;
    float4 modulationColor;
};

vertex VertexOut_PNUC pbr_pnuc_vertex_shader(VertexIn_PNUC in [[stage_in]],
                                               constant float4x4 &model [[buffer(1)]],
                                               constant float4x4 &view [[buffer(2)]],
                                               constant float4x4 &projection [[buffer(3)]],
                                               constant float3x3 &normalMatrix [[buffer(4)]]) {
    VertexOut_PNUC out;

    float4x4 mvpMatrix = projection * view * model;

    out.position = mvpMatrix * float4(in.position, 1.0);
    out.worldPosition = (model * float4(in.position, 1.0)).xyz;
    out.normal = normalize(normalMatrix * in.normal);
    out.uv = in.uv;
    out.modulationColor = in.modulationColor;
    return out;
}

fragment float4 pbr_pnuc_fragment_shader(VertexOut_PNUC in [[stage_in]],
                                         constant PBRSceneUniforms &uniforms [[buffer(0)]],
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

    float3 albedo = baseColorTexture.sample(baseColorSampler, in.uv).rgb * in.modulationColor.rgb;
    float metallic = metallicRoughnessTexture.sample(metallicRoughnessSampler, in.uv).b;
    float roughness = metallicRoughnessTexture.sample(metallicRoughnessSampler, in.uv).g;
    float ambientOcclusion = occlusionTexture.sample(occlusionSampler, in.uv).r;

    // Default normal from vertex normal
    float3 normal = normalize(in.normal);
    if (normalTexture.get_width() > 0 && normalTexture.get_height() > 0) {
        float3 normalSample = normalTexture.sample(normalSampler, in.uv).rgb;
        float3 tangentNormal = normalSample * 2.0 - 1.0;

        // Construct a TBN matrix assuming the normal is Z and use a fixed tangent space
        float3x3 TBN = make_tbn(normal);

        normal = normalize(TBN * tangentNormal);
    }
    float3 worldPosition = in.worldPosition;
    float3 viewPosition = uniforms.viewPosition;

    // Direct lighting
    float3 directLighting = compute_direct_lighting(normal,
                                                    worldPosition,
                                                    albedo,
                                                    metallic,
                                                    roughness,
                                                    uniforms.viewPosition,
                                                    uniforms.lightPosition,
                                                    uniforms.ambientLightColor);

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
    float3 emissive = emissiveTexture.sample(emissiveSampler, in.uv).rgb;

    // Final color
    float3 color = directLighting + indirectLighting + emissive;

    return float4(color, 1.0);
}

// MARK: - Shaders for PNTU(Position, Normal, Tangent, UV)

struct VertexIn_PNTU {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float4 tangent [[attribute(2)]];
    float2 uv [[attribute(3)]];
};

struct VertexOut_PNTU {
    float4 position [[position]];
    float3 worldPosition;
    float3 normal;
    float4 tangent;
    float2 uv;
};

vertex VertexOut_PNTU pbr_pntu_vertex_shader(VertexIn_PNTU in [[stage_in]],
                                             constant float4x4 &model [[buffer(1)]],
                                             constant float4x4 &view [[buffer(2)]],
                                             constant float4x4 &projection [[buffer(3)]],
                                             constant float3x3 &normalMatrix [[buffer(4)]]) {
    VertexOut_PNTU out;

    float4x4 mvpMatrix = projection * view * model;

    out.position = mvpMatrix * float4(in.position, 1.0);
    out.worldPosition = (model * float4(in.position, 1.0)).xyz;
    out.normal = normalize(normalMatrix * in.normal);
    out.tangent = normalize(float4(normalMatrix * in.tangent.xyz, in.tangent.w));
    out.uv = in.uv;
    return out;
}

fragment float4 pbr_pntu_fragment_shader(VertexOut_PNTU in [[stage_in]],
                                         constant PBRSceneUniforms &uniforms [[buffer(0)]],
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

    float3 albedo = baseColorTexture.sample(baseColorSampler, in.uv).rgb;
    float metallic = metallicRoughnessTexture.sample(metallicRoughnessSampler, in.uv).b;
    float roughness = metallicRoughnessTexture.sample(metallicRoughnessSampler, in.uv).g;
    float ambientOcclusion = occlusionTexture.sample(occlusionSampler, in.uv).r;

    // Default normal from vertex normal
    float3 normal = float3(0, 0, 1);
    if (normalTexture.get_width() > 0 && normalTexture.get_height() > 0) {
        float3 N = normalize(in.normal);
        float3 normalSample = normalTexture.sample(normalSampler, in.uv).rgb;
        float3 normalTexValue = normalSample * 2.0 - 1.0;
        float3x3 TBN = make_tbn(N, in.tangent.rgb, in.tangent.w);
        normal = normalize(TBN * normalTexValue);
    }
    float3 worldPosition = in.worldPosition;
    float3 viewPosition = uniforms.viewPosition;

    // Direct lighting
    float3 directLighting = compute_direct_lighting(normal,
                                                    worldPosition,
                                                    albedo,
                                                    metallic,
                                                    roughness,
                                                    uniforms.viewPosition,
                                                    uniforms.lightPosition,
                                                    uniforms.ambientLightColor);

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
    float3 emissive = emissiveTexture.sample(emissiveSampler, in.uv).rgb;

    // Final color
    float3 color = directLighting + indirectLighting + emissive;

    return float4(color, 1.0);
}
