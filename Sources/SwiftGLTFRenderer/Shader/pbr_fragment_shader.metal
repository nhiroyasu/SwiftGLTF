#include <metal_stdlib>
#include "includes/helper.h"
#include "includes/refract.h"
#include "includes/env_arguments.h"
#include "includes/screen_arguments.h"
#include "includes/pbr_lighting.h"
#include "includes/pbr_vertex.h"
#include "includes/pbr_arguments.h"
#include "../../SwiftGLTFShaderTypes/includes/pbr.h"

using namespace metal;

fragment float4 pbr_fragment_shader(PBRVertexOut in [[stage_in]],
                                    constant PBRFragmentArguments &fragArgs [[buffer(PBRFragmentShaderArgsBuffer)]],
                                    constant PBREnvMapArguments &envMapArgs [[buffer(PBRFragmentShaderEnvMapArgsBuffer)]],
                                    constant SceneUniforms &scene [[buffer(PBRFragmentShaderSceneUniformsBuffer)]],
                                    constant PBRScreenColorArguments &scArgs [[buffer(PBRFragmentShaderScreenColorBuffer)]],
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
    texturecube<float> prefilterSheenMap = envMapArgs.prefilterSheenMap;

    float2 uv0 = in.uv;
    float2 uv1 = in.uv1;
    float4 modulationColor = in.modulationColor;
    // Screen UV from fragment position and viewport size
    float2 screenUV = float2(in.position.xy) / scene.viewportSize;
    screenUV = clamp(screenUV, float2(0.0), float2(1.0));

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
    normal = fragArgs.material.doubleSided != 0 && !isFrontFacing ? -normal : normal;

    // Clearcoat parameters
    float clearcoatFactor = saturate(mUni.clearcoatFactors.x);
    uint ccCoord = fragArgs.clearcoatTexCoord;
    float2 uvCC = (ccCoord == 0) ? uv0 : uv1;
    if (fragArgs.hasClearcoatTexture) {
        float ccSample = fragArgs.clearcoatTexture.sample(fragArgs.clearcoatSampler, uvCC).r;
        clearcoatFactor *= ccSample;
    }
    clearcoatFactor = saturate(clearcoatFactor);

    float clearcoatRoughness = clamp(mUni.clearcoatFactors.y, 0.0, 1.0);
    uint ccRCoord = fragArgs.clearcoatRoughnessTexCoord;
    float2 uvCCR = (ccRCoord == 0) ? uv0 : uv1;
    if (fragArgs.hasClearcoatRoughnessTexture) {
        float ccRoughSample = fragArgs.clearcoatRoughnessTexture.sample(fragArgs.clearcoatRoughnessSampler, uvCCR).g;
        clearcoatRoughness *= ccRoughSample;
    }
    clearcoatRoughness = clamp(clearcoatRoughness, 0.0, 1.0);

    float clearcoatNormalScale = mUni.clearcoatFactors.z;
    float3 clearcoatNormal = normal;
    if (fragArgs.hasClearcoatNormalTexture) {
        uint ccNCoord = fragArgs.clearcoatNormalTexCoord;
        float2 uvCCN = (ccNCoord == 0) ? uv0 : uv1;
        float3 ccSample = fragArgs.clearcoatNormalTexture.sample(fragArgs.clearcoatNormalSampler, uvCCN).rgb * 2.0 - 1.0;
        float2 ccXY = ccSample.xy * clearcoatNormalScale;
        float ccZ = sqrt(saturate(1.0 - dot(ccXY, ccXY)));
        float3 ccTangentNormal = normalize(float3(ccXY, ccZ));
        clearcoatNormal = normalize(TBN * ccTangentNormal);
        clearcoatNormal = fragArgs.material.doubleSided != 0 && !isFrontFacing ? -clearcoatNormal : clearcoatNormal;
    }

    // Specular extension
    uint sCoord = fragArgs.specularTexCoord;
    float2 uvS = (sCoord == 0) ? uv0 : uv1;
    float specularFactor = mUni.specularFactor;
    specularFactor *= fragArgs.hasSpecularTexture ? fragArgs.specularTexture.sample(fragArgs.specularSampler, uvS).r : 1.0;

    uint scCoord = fragArgs.specularColorTexCoord;
    float2 uvSC = (scCoord == 0) ? uv0 : uv1;
    float3 specularColor = mUni.specularFactorColor.xyz;
    specularColor *= fragArgs.hasSpecularColorTexture ? fragArgs.specularColorTexture.sample(fragArgs.specularColorSampler, uvSC).rgb : float3(1.0);

    // Sheen extension
    uint shcCoord = fragArgs.sheenColorTexCoord;
    float2 uvShC = (shcCoord == 0) ? uv0 : uv1;
    float3 sheenColor = mUni.sheenColorRoughness.xyz;
    sheenColor *= fragArgs.hasSheenColorTexture ? fragArgs.sheenColorTexture.sample(fragArgs.sheenColorSampler, uvShC).rgb : float3(1.0);
    sheenColor = clamp(sheenColor, float3(0.0), float3(1.0));

    uint shrCoord = fragArgs.sheenRoughnessTexCoord;
    float2 uvShR = (shrCoord == 0) ? uv0 : uv1;
    float sheenRoughness = mUni.sheenColorRoughness.w;
    sheenRoughness *= fragArgs.hasSheenRoughnessTexture ? fragArgs.sheenRoughnessTexture.sample(fragArgs.sheenRoughnessSampler, uvShR).g : 1.0;
    sheenRoughness = clamp(sheenRoughness, 0.0, 1.0);

    // Select UV coordinate for transmission
    uint tCoord = fragArgs.transmissionTexCoord;
    float2 uvT = (tCoord == 0) ? uv0 : uv1;
    // Transmission factor
    float transmission = mUni.transmissionThicknessDistance.x;
    transmission *= fragArgs.hasTransmissionTexture
    ? fragArgs.transmissionTexture.sample(fragArgs.transmissionSampler, uvT).r
    : 1.0;

    // Select UV coordinate for thickness
    uint thCoord = fragArgs.thicknessTexCoord;
    float2 uvTh = (thCoord == 0) ? uv0 : uv1;
    // Thickness
    float thickness = mUni.transmissionThicknessDistance.y;
    thickness *= fragArgs.hasThicknessTexture
    ? fragArgs.thicknessTexture.sample(fragArgs.thicknessSampler, uvTh).r
    : 1.0;

    // Attenuation
    float attenDist = mUni.transmissionThicknessDistance.z;
    float3 attenColor = mUni.attenuationColor.rgb;

    // Transmittance calculation
    // (Beer-Lambert): sigma_a = -ln(color) / distance;  T = exp(-sigma_a * thickness)
    float3 attColor = clamp(attenColor, float3(1e-6), float3(1.0));
    float3 sigma_a = attenDist > 0.0 ? -log(attColor) / attenDist : float3(0.0);
    float3 attenuation = thickness > 0.0 ? exp(-sigma_a * thickness) : float3(1.0);

    // Background color from previous pass (with refraction offset)
    float maxMip = scArgs.useSceneColor ? scArgs.sceneColorTexture.get_num_mip_levels() - 1 : 0;
    float lod = clamp(roughness * maxMip, 0.0, maxMip);
    float ior = mUni.ior;
    /* Minimum refraction model (not physically accurate)
     float eta = 1.0 / max(ior, 1e-5);
     float3 R = refract(-normalize(viewPosition), normalize(normal), eta);
     float2 dUV = R.xy * thickness * 0.1;
     */
    float2 dUV = refract_uv_offset_thin_slab(normalize(in.positionVS),
                                             normalize(in.normalVS),
                                             thickness,
                                             ior,
                                             in.positionVS,
                                             scene.fov,
                                             scene.viewportSize,
                                             scene.camRight,
                                             scene.camUp);
    float3 Lbg = scArgs.useSceneColor
    ? scArgs.sceneColorTexture.sample(scArgs.sceneColorSampler, screenUV + dUV, level(lod)).rgb
    : float3(0.0);

    float3 worldPosition = in.worldPosition;
    float3 viewPosition = scene.viewPosition;

    constexpr sampler brdfLUTSampler(mag_filter::linear, min_filter::linear, s_address::clamp_to_edge, t_address::clamp_to_edge);

    // Direct lighting
    float3 directLighting = compute_direct_lighting(normal,
                                                    worldPosition,
                                                    albedo,
                                                    metallic,
                                                    roughness,
                                                    transmission,
                                                    viewPosition,
                                                    scene.lightPosition,
                                                    scene.ambientLightColor,
                                                    ior,
                                                    specularFactor,
                                                    specularColor,
                                                    sheenColor,
                                                    sheenRoughness,
                                                    clearcoatFactor,
                                                    clearcoatRoughness,
                                                    clearcoatNormal,
                                                    brdfLUT,
                                                    brdfLUTSampler);

    // Indirect lighting
    float3 indirectLighting = compute_indirect_lighting(normal,
                                                        worldPosition,
                                                        viewPosition,
                                                        albedo,
                                                        metallic,
                                                        roughness,
                                                        ambientOcclusion,
                                                        transmission,
                                                        clearcoatFactor,
                                                        clearcoatRoughness,
                                                        clearcoatNormal,
                                                        prefilterEnvMap,
                                                        irradianceMap,
                                                        brdfLUT,
                                                        ior,
                                                        specularFactor,
                                                        specularColor,
                                                        sheenColor,
                                                        sheenRoughness,
                                                        prefilterSheenMap);

    // Transmission effect (approximation)
    float3 transmissionLighting = compute_transmission_lighting(Lbg,
                                                                normal,
                                                                albedo,
                                                                metallic,
                                                                transmission,
                                                                attenuation,
                                                                worldPosition,
                                                                viewPosition,
                                                                ior,
                                                                specularFactor,
                                                                specularColor);
    transmissionLighting *= (1.0 - clearcoatFactor);

    // Final color
    float3 color = directLighting + indirectLighting + transmissionLighting + emissive;

    // Alpha: baseColor.a * modulation.a * materialFactor.a
    float baseAlpha = fragArgs.hasBaseColorTexture ? baseColorTexture.sample(baseColorSampler, uvBC).a : 1.0;
    float alpha = baseAlpha * modulationColor.a * mUni.baseColorFactor.a;

    // Alpha test (MASK)
    if (fragArgs.alphaMode == AlphaModeMask && alpha < fragArgs.alphaCutoff) {
        discard_fragment();
    }

    // Premultiply if blending (BLEND)
    color *= fragArgs.alphaMode == AlphaModeBlend ? alpha : 1.0;

    return float4(color, alpha);
}
