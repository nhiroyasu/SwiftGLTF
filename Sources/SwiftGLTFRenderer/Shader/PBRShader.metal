#include <metal_stdlib>
#include "../../SwiftGLTFShaderTypes/includes/pbr.h"
#include "includes/metal_helper.h"
using namespace metal;

enum AlphaMode : uint {
    AlphaModeOpaque = 0,
    AlphaModeMask   = 1,
    AlphaModeBlend  = 2
};

struct MorphApplyResult {
    float3 pos;
    float3 normal;
    float4 tangent;
};

// MARK: - Shader Structures

struct VertexIn {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float4 tangent [[attribute(2)]];
    float2 uv [[attribute(3)]];
    float2 uv1 [[attribute(4)]];
    float4 modulationColor [[attribute(5)]];
    ushort4 joints [[attribute(6)]];
    float4 weights [[attribute(7)]];
};

struct PBRVertexOut {
    float4 position [[position]];
    float3 worldPosition;
    float3 normal;
    float4 tangent;
    float2 uv;
    float2 uv1;
    float4 modulationColor;
};

struct PBRVertexArguments {
    constant float4x4 &model [[id(0)]];
    constant float4x4 &inverseModel [[id(1)]];
    bool hasSkinning [[id(2)]];
    constant float4x4 *globalJointMatrices [[id(3)]];
    // Morph targets (optional)
    bool hasMorph [[id(4)]];
    uint morphTargetCount [[id(5)]];
    constant float *morphWeights [[id(6)]];
    constant float *morphInterleaved0 [[id(7)]];
    constant float *morphInterleaved1 [[id(8)]];
    constant float *morphInterleaved2 [[id(9)]];
    constant float *morphInterleaved3 [[id(10)]];
    constant float *morphInterleaved4 [[id(11)]];
    constant float *morphInterleaved5 [[id(12)]];
    constant float *morphInterleaved6 [[id(13)]];
    constant float *morphInterleaved7 [[id(14)]];
};

struct PBRFragmentArguments {
    constant PBRMaterialUniforms &material [[id(0)]];
    // BaseColor: Texture -> Sampler -> TexCoord
    bool hasBaseColorTexture [[id(1)]];
    texture2d<float> baseColorTexture [[id(2)]];
    sampler baseColorSampler [[id(3)]];
    uint baseColorTexCoord [[id(4)]];
    // Normal: Texture -> Sampler -> TexCoord
    bool hasNormalTexture [[id(5)]];
    texture2d<float> normalTexture [[id(6)]];
    sampler normalSampler [[id(7)]];
    uint normalTexCoord [[id(8)]];
    // MetallicRoughness: Texture -> Sampler -> TexCoord
    bool hasMetallicRoughnessTexture [[id(9)]];
    texture2d<float> metallicRoughnessTexture [[id(10)]];
    sampler metallicRoughnessSampler [[id(11)]];
    uint metallicRoughnessTexCoord [[id(12)]];
    // Emissive: Texture -> Sampler -> TexCoord
    bool hasEmissiveTexture [[id(13)]];
    texture2d<float> emissiveTexture [[id(14)]];
    sampler emissiveSampler [[id(15)]];
    uint emissiveTexCoord [[id(16)]];
    // Occlusion: Texture -> Sampler -> TexCoord
    bool hasOcclusionTexture [[id(17)]];
    texture2d<float> occlusionTexture [[id(18)]];
    sampler occlusionSampler [[id(19)]];
    uint occlusionTexCoord [[id(20)]];
    // Alpha controls
    AlphaMode alphaMode [[id(21)]]; // 0: OPAQUE, 1: MASK, 2: BLEND
    float alphaCutoff [[id(22)]]; // valid when alphaMode == MASK
};

struct PBREnvMapArguments {
    texturecube<float> prefilterEnvMap [[id(0)]];
    texturecube<float> irradianceMap [[id(1)]];
    texture2d<float> brdfLUT [[id(2)]];
};

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

inline float4x4 compute_skin_matrix(constant float4x4 *globalJointMatrices,
                             float4x4 inverseGlobalTransform,
                             ushort4 joints,
                             float4 weights) {
    float4x4 skinMatrix = weights.x * inverseGlobalTransform * globalJointMatrices[joints.x] +
                          weights.y * inverseGlobalTransform * globalJointMatrices[joints.y] +
                          weights.z * inverseGlobalTransform * globalJointMatrices[joints.z] +
                          weights.w * inverseGlobalTransform * globalJointMatrices[joints.w];
    return skinMatrix;
}

inline MorphApplyResult apply_morph(float3 pos,
                                    float3 normal,
                                    float4 tangent,
                                    constant PBRVertexArguments &args,
                                    uint vid) {
    if (!args.hasMorph) {
        return { pos, normal, tangent };
    }
    uint count = min(args.morphTargetCount, (uint)8);
    for (uint i = 0; i < count; ++i) {
        float w = args.morphWeights[i];
        if (w == 0.0) { continue; }
        constant float *buf = nullptr;
        switch (i) {
            case 0: buf = args.morphInterleaved0; break;
            case 1: buf = args.morphInterleaved1; break;
            case 2: buf = args.morphInterleaved2; break;
            case 3: buf = args.morphInterleaved3; break;
            case 4: buf = args.morphInterleaved4; break;
            case 5: buf = args.morphInterleaved5; break;
            case 6: buf = args.morphInterleaved6; break;
            case 7: buf = args.morphInterleaved7; break;
            default: break;
        }
        if (buf == nullptr) { continue; }
        uint base = vid * 9; // 9 floats per vertex (pos3+normal3+tan3)
        float3 dpos = float3(buf[base + 0], buf[base + 1], buf[base + 2]);
        float3 dnormal = float3(buf[base + 3], buf[base + 4], buf[base + 5]);
        float3 dtan = float3(buf[base + 6], buf[base + 7], buf[base + 8]);
        pos += dpos * w;
        normal += dnormal * w;
        tangent.xyz += dtan * w;
    }
    normal = normalize(normal);
    tangent = float4(normalize(tangent.xyz), tangent.w); // keep sign in w
    return { pos, normal, tangent };
}

// MARK: - PBR Shader

vertex PBRVertexOut pbr_vertex_shader(VertexIn in [[stage_in]],
                                      constant PBRVertexArguments &args [[buffer(1)]],
                                      constant PBRVertexVariableParameters &params [[buffer(2)]],
                                      uint vid [[vertex_id]])
{
    PBRVertexOut out;

    // Apply morph targets in model space before skinning
    float3 pos = in.position;
    float3 normal = in.normal;
    float4 tan = in.tangent;
    MorphApplyResult morphed = apply_morph(pos, normal, tan, args, vid);
    pos = morphed.pos;
    normal = morphed.normal;
    tan = morphed.tangent;

    float4x4 skinMatrix = args.hasSkinning
    ? compute_skin_matrix(args.globalJointMatrices, args.inverseModel, in.joints, in.weights)
    : float4x4(1.0);
    float4x4 modelTransform = params.externalTransform * args.model * skinMatrix;
    float4x4 mvpTransform = params.projection * params.view * modelTransform;

    float3x3 normalTransform = transpose(inverse(_float3x3(modelTransform)));

    out.position = mvpTransform * float4(pos, 1.0);
    out.worldPosition = (modelTransform * float4(pos, 1.0)).xyz;
    out.normal = normalize(normalTransform * normal);
    out.tangent = normalize(float4(normalTransform * tan.xyz, tan.w));
    out.uv = in.uv;
    out.uv1 = in.uv1;
    out.modulationColor = in.modulationColor;
    return out;
}

fragment float4 pbr_fragment_shader(PBRVertexOut in [[stage_in]],
                                    constant PBRFragmentArguments &fragArgs [[buffer(0)]],
                                    constant PBREnvMapArguments &envMapArgs [[buffer(1)]],
                                    constant PBRFragmentVariableParameters &params [[buffer(2)]],
                                    bool isFrontFacing [[front_facing]])
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

    float2 uv0 = in.uv;
    float2 uv1 = in.uv1;
    float4 modulationColor = in.modulationColor;

    // Select UV coordinate for base color
    uint bcCoord = fragArgs.baseColorTexCoord;
    float2 uvBC = (bcCoord == 0) ? uv0 : uv1;
    // Apply base color texture, vertex modulation color, and material base color factor
    float3 albedo = fragArgs.hasBaseColorTexture
    ? baseColorTexture.sample(baseColorSampler, uvBC).rgb * modulationColor.rgb * mUni.baseColorFactor.rgb
    : float3(1, 1, 1) * modulationColor.rgb * mUni.baseColorFactor.rgb;

    // Select UV coordinate for metallic-roughness
    uint mrCoord = fragArgs.metallicRoughnessTexCoord;
    float2 uvMR = (mrCoord == 0) ? uv0 : uv1;
    // Sample metallic-roughness and apply material factors
    float metallic = fragArgs.hasMetallicRoughnessTexture
    ? metallicRoughnessTexture.sample(metallicRoughnessSampler, uvMR).b * mUni.metalRoughnessOcclusion.x
    : 1.0 * mUni.metalRoughnessOcclusion.x;
    float roughness = fragArgs.hasMetallicRoughnessTexture
    ? metallicRoughnessTexture.sample(metallicRoughnessSampler, uvMR).g * mUni.metalRoughnessOcclusion.y
    : 1.0 * mUni.metalRoughnessOcclusion.y;

    // Select UV coordinate for emissive
    uint eCoord = fragArgs.emissiveTexCoord;
    float2 uvE = (eCoord == 0) ? uv0 : uv1;
    // Emissive lighting: apply material emissive factor
    float3 emissive = fragArgs.hasEmissiveTexture
    ? emissiveTexture.sample(emissiveSampler, uvE).rgb * mUni.emissiveFactor.rgb
    : float3(1, 1, 1) * mUni.emissiveFactor.rgb;

    // Select UV coordinate for occlusion
    uint ocCoord = fragArgs.occlusionTexCoord;
    float2 uvOC = (ocCoord == 0) ? uv0 : uv1;
    // Ambient occlusion: apply material occlusion factor
    float ambientOcclusion = fragArgs.hasOcclusionTexture
    ? occlusionTexture.sample(occlusionSampler, uvOC).r * mUni.metalRoughnessOcclusion.z
    : 1.0 * mUni.metalRoughnessOcclusion.z;

    float3 N = normalize(in.normal);
    float3x3 TBN = make_tbn(N, in.tangent.xyz, in.tangent.w);

    // Select UV coordinate for normal map
    uint nCoord = fragArgs.normalTexCoord;
    float2 uvN = (nCoord == 0) ? uv0 : uv1;
    float3 normalTexValue = fragArgs.hasNormalTexture
    ? normalTexture.sample(normalSampler, uvN).rgb * 2.0 - 1.0
    : float3(0, 0, 1);
    float3 normal = normalize(TBN * normalTexValue);
    // Flip normal for back faces when double-sided
    if (fragArgs.material.doubleSided != 0 && !isFrontFacing) {
        normal = -normal;
    }

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

    // Alpha: baseColor.a * modulation.a * materialFactor.a
    float baseAlpha = 1.0;
    if (fragArgs.hasBaseColorTexture) {
        baseAlpha = baseColorTexture.sample(baseColorSampler, uvBC).a;
    }
    float alpha = baseAlpha * modulationColor.a * mUni.baseColorFactor.a;

    // Alpha test (MASK)
    if (fragArgs.alphaMode == AlphaModeMask) {
        if (alpha < fragArgs.alphaCutoff) {
            discard_fragment();
        }
        alpha = 1.0; // masked surfaces write solid pixels
    }

    // Final color
    float3 color = directLighting + indirectLighting + emissive;
    // Premultiply if blending (BLEND)
    if (fragArgs.alphaMode == AlphaModeBlend) {
        color *= alpha;
    } else {
        alpha = 1.0;
    }
    return float4(color, alpha);
}
