#ifndef pbr_arguments_h
#define pbr_arguments_h

#include "../../../SwiftGLTFShaderTypes/includes/pbr.h"

struct PBRVertexArguments {
    constant float4x4 &model                [[id(PBRVertexArgIdModel)]];
    constant float4x4 &inverseModel         [[id(PBRVertexArgIdInverseModel)]];

    // Morph targets (optional)
    uint morphTargetCount                   [[id(PBRVertexArgIdMorphTargetCount)]];
    constant float *morphDefaultWeights     [[id(PBRVertexArgIdMorphDefaultWeights)]];
    constant float *morphInterleaved0       [[id(PBRVertexArgIdMorphInterleaved0)]];
    constant float *morphInterleaved1       [[id(PBRVertexArgIdMorphInterleaved1)]];
    constant float *morphInterleaved2       [[id(PBRVertexArgIdMorphInterleaved2)]];
    constant float *morphInterleaved3       [[id(PBRVertexArgIdMorphInterleaved3)]];
    constant float *morphInterleaved4       [[id(PBRVertexArgIdMorphInterleaved4)]];
    constant float *morphInterleaved5       [[id(PBRVertexArgIdMorphInterleaved5)]];
    constant float *morphInterleaved6       [[id(PBRVertexArgIdMorphInterleaved6)]];
    constant float *morphInterleaved7       [[id(PBRVertexArgIdMorphInterleaved7)]];

    int64_t transformIndex                  [[id(PBRVertexArgIdTransformIndex)]];
    int64_t morphDispatchIndex              [[id(PBRVertexArgIdMorphDispatchIndex)]]; // equal to `transformIndex`
    SkinDispatch skinDispatch               [[id(PBRVertexArgIdSkinDispatch)]];
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
};

#endif /* pbr_arguments_h */
