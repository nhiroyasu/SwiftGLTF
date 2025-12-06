#ifndef pbr_arguments_h
#define pbr_arguments_h

#include "../../../SwiftGLTFShaderTypes/includes/pbr.h"
#include <metal_stdlib>
using namespace metal;

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
    // Transmission (KHR_materials_transmission)
    bool hasTransmissionTexture [[id(23)]];
    texture2d<float> transmissionTexture [[id(24)]];
    sampler transmissionSampler [[id(25)]];
    uint transmissionTexCoord [[id(26)]];
    // Volume thickness (KHR_materials_volume)
    bool hasThicknessTexture [[id(27)]];
    texture2d<float> thicknessTexture [[id(28)]];
    sampler thicknessSampler [[id(29)]];
    uint thicknessTexCoord [[id(30)]];
    // Specular (KHR_materials_specular)
    bool hasSpecularTexture [[id(31)]]; // R: specularFactor multiplier
    texture2d<float> specularTexture [[id(32)]];
    sampler specularSampler [[id(33)]];
    uint specularTexCoord [[id(34)]];
    bool hasSpecularColorTexture [[id(35)]]; // RGB: specularColor multiplier
    texture2d<float> specularColorTexture [[id(36)]];
    sampler specularColorSampler [[id(37)]];
    uint specularColorTexCoord [[id(38)]];
    // Sheen (KHR_materials_sheen)
    bool hasSheenColorTexture [[id(39)]]; // RGB
    texture2d<float> sheenColorTexture [[id(40)]];
    sampler sheenColorSampler [[id(41)]];
    uint sheenColorTexCoord [[id(42)]];
    bool hasSheenRoughnessTexture [[id(43)]]; // G channel
    texture2d<float> sheenRoughnessTexture [[id(44)]];
    sampler sheenRoughnessSampler [[id(45)]];
    uint sheenRoughnessTexCoord [[id(46)]];
    // Clearcoat (KHR_materials_clearcoat)
    bool hasClearcoatTexture [[id(47)]];
    texture2d<float> clearcoatTexture [[id(48)]];
    sampler clearcoatSampler [[id(49)]];
    uint clearcoatTexCoord [[id(50)]];
    bool hasClearcoatRoughnessTexture [[id(51)]];
    texture2d<float> clearcoatRoughnessTexture [[id(52)]];
    sampler clearcoatRoughnessSampler [[id(53)]];
    uint clearcoatRoughnessTexCoord [[id(54)]];
    bool hasClearcoatNormalTexture [[id(55)]];
    texture2d<float> clearcoatNormalTexture [[id(56)]];
    sampler clearcoatNormalSampler [[id(57)]];
    uint clearcoatNormalTexCoord [[id(58)]];
    float clearcoatNormalScale [[id(59)]];
    float4 baseColorTransformOffsetScale [[id(60)]];
    float baseColorTransformRotation [[id(61)]];
    float4 normalTransformOffsetScale [[id(62)]];
    float normalTransformRotation [[id(63)]];
    float4 metallicRoughnessTransformOffsetScale [[id(64)]];
    float metallicRoughnessTransformRotation [[id(65)]];
    float4 emissiveTransformOffsetScale [[id(66)]];
    float emissiveTransformRotation [[id(67)]];
    float4 occlusionTransformOffsetScale [[id(68)]];
    float occlusionTransformRotation [[id(69)]];
    float4 transmissionTransformOffsetScale [[id(70)]];
    float transmissionTransformRotation [[id(71)]];
    float4 thicknessTransformOffsetScale [[id(72)]];
    float thicknessTransformRotation [[id(73)]];
    float4 specularTransformOffsetScale [[id(74)]];
    float specularTransformRotation [[id(75)]];
    float4 specularColorTransformOffsetScale [[id(76)]];
    float specularColorTransformRotation [[id(77)]];
    float4 sheenColorTransformOffsetScale [[id(78)]];
    float sheenColorTransformRotation [[id(79)]];
    float4 sheenRoughnessTransformOffsetScale [[id(80)]];
    float sheenRoughnessTransformRotation [[id(81)]];
    float4 clearcoatTransformOffsetScale [[id(82)]];
    float clearcoatTransformRotation [[id(83)]];
    float4 clearcoatRoughnessTransformOffsetScale [[id(84)]];
    float clearcoatRoughnessTransformRotation [[id(85)]];
    float4 clearcoatNormalTransformOffsetScale [[id(86)]];
    float clearcoatNormalTransformRotation [[id(87)]];
};

#endif /* pbr_arguments_h */
