#include "includes/default_arguments.h"
#include <metal_stdlib>
using namespace metal;

constant PBRMaterialUniforms kDefaultPBRMaterial = {
    float4(1.0f, 1.0f, 1.0f, 1.0f),          // baseColorFactor (RGBA)
    float4(1.0f, 1.0f, 1.0f, 0.0f),          // metalRoughnessOcclusion (metallic, roughness, occlusion, padding)
    float4(0.0f, 0.0f, 0.0f, 0.0f),          // emissiveFactor (RGB, padding)
    0u,                                      // doubleSided flag (0 = single sided)
    0u,                                      // isUnlit flag
    float4(0.0f, 0.0f, -1.0f, 0.0f),         // transmissionThicknessDistance (transmission, thickness, attenuationDistance, padding)
    float4(1.0f, 1.0f, 1.0f, 0.0f),          // attenuationColor (RGB, padding)
    1.5f,                                    // index of refraction (ior)
    1.0f,                                    // specularFactor
    float4(1.0f, 1.0f, 1.0f, 0.0f),          // specularFactorColor (RGB, padding)
    float4(0.0f, 0.0f, 0.0f, 0.0f),          // sheenColorRoughness (sheenColor RGB, sheenRoughness)
    float4(0.0f, 0.0f, 1.0f, 0.0f)           // clearcoatFactors (factor, roughness, normalScale, padding)
};

// TODO: It is preferable to set the texture and sampler to null.
PBRFragmentArguments makeDefaultPBRFragmentArguments()
{
    return {
        kDefaultPBRMaterial,                  // material uniforms
        false,                                // hasBaseColorTexture
        texture2d<float>(),                   // baseColorTexture
        sampler(),                            // baseColorSampler
        0u,                                   // baseColorTexCoord
        false,                                // hasNormalTexture
        texture2d<float>(),                   // normalTexture
        sampler(),                            // normalSampler
        0u,                                   // normalTexCoord
        false,                                // hasMetallicRoughnessTexture
        texture2d<float>(),                   // metallicRoughnessTexture
        sampler(),                            // metallicRoughnessSampler
        0u,                                   // metallicRoughnessTexCoord
        false,                                // hasEmissiveTexture
        texture2d<float>(),                   // emissiveTexture
        sampler(),                            // emissiveSampler
        0u,                                   // emissiveTexCoord
        false,                                // hasOcclusionTexture
        texture2d<float>(),                   // occlusionTexture
        sampler(),                            // occlusionSampler
        0u,                                   // occlusionTexCoord
        AlphaModeOpaque,                      // alphaMode
        0.5f,                                 // alphaCutoff
        false,                                // hasTransmissionTexture
        texture2d<float>(),                   // transmissionTexture
        sampler(),                            // transmissionSampler
        0u,                                   // transmissionTexCoord
        false,                                // hasThicknessTexture
        texture2d<float>(),                   // thicknessTexture
        sampler(),                            // thicknessSampler
        0u,                                   // thicknessTexCoord
        false,                                // hasSpecularTexture
        texture2d<float>(),                   // specularTexture
        sampler(),                            // specularSampler
        0u,                                   // specularTexCoord
        false,                                // hasSpecularColorTexture
        texture2d<float>(),                   // specularColorTexture
        sampler(),                            // specularColorSampler
        0u,                                   // specularColorTexCoord
        false,                                // hasSheenColorTexture
        texture2d<float>(),                   // sheenColorTexture
        sampler(),                            // sheenColorSampler
        0u,                                   // sheenColorTexCoord
        false,                                // hasSheenRoughnessTexture
        texture2d<float>(),                   // sheenRoughnessTexture
        sampler(),                            // sheenRoughnessSampler
        0u,                                   // sheenRoughnessTexCoord
        false,                                // hasClearcoatTexture
        texture2d<float>(),                   // clearcoatTexture
        sampler(),                            // clearcoatSampler
        0u,                                   // clearcoatTexCoord
        false,                                // hasClearcoatRoughnessTexture
        texture2d<float>(),                   // clearcoatRoughnessTexture
        sampler(),                            // clearcoatRoughnessSampler
        0u,                                   // clearcoatRoughnessTexCoord
        false,                                // hasClearcoatNormalTexture
        texture2d<float>(),                   // clearcoatNormalTexture
        sampler(),                            // clearcoatNormalSampler
        0u,                                   // clearcoatNormalTexCoord
        1.0f,                                 // clearcoatNormalScale
        float4(0.0f, 0.0f, 1.0f, 1.0f),       // baseColorTransformOffsetScale (offset.xy, scale.xy)
        0.0f,                                 // baseColorTransformRotation
        float4(0.0f, 0.0f, 1.0f, 1.0f),       // normalTransformOffsetScale
        0.0f,                                 // normalTransformRotation
        float4(0.0f, 0.0f, 1.0f, 1.0f),       // metallicRoughnessTransformOffsetScale
        0.0f,                                 // metallicRoughnessTransformRotation
        float4(0.0f, 0.0f, 1.0f, 1.0f),       // emissiveTransformOffsetScale
        0.0f,                                 // emissiveTransformRotation
        float4(0.0f, 0.0f, 1.0f, 1.0f),       // occlusionTransformOffsetScale
        0.0f,                                 // occlusionTransformRotation
        float4(0.0f, 0.0f, 1.0f, 1.0f),       // transmissionTransformOffsetScale
        0.0f,                                 // transmissionTransformRotation
        float4(0.0f, 0.0f, 1.0f, 1.0f),       // thicknessTransformOffsetScale
        0.0f,                                 // thicknessTransformRotation
        float4(0.0f, 0.0f, 1.0f, 1.0f),       // specularTransformOffsetScale
        0.0f,                                 // specularTransformRotation
        float4(0.0f, 0.0f, 1.0f, 1.0f),       // specularColorTransformOffsetScale
        0.0f,                                 // specularColorTransformRotation
        float4(0.0f, 0.0f, 1.0f, 1.0f),       // sheenColorTransformOffsetScale
        0.0f,                                 // sheenColorTransformRotation
        float4(0.0f, 0.0f, 1.0f, 1.0f),       // sheenRoughnessTransformOffsetScale
        0.0f,                                 // sheenRoughnessTransformRotation
        float4(0.0f, 0.0f, 1.0f, 1.0f),       // clearcoatTransformOffsetScale
        0.0f,                                 // clearcoatTransformRotation
        float4(0.0f, 0.0f, 1.0f, 1.0f),       // clearcoatRoughnessTransformOffsetScale
        0.0f,                                 // clearcoatRoughnessTransformRotation
        float4(0.0f, 0.0f, 1.0f, 1.0f),       // clearcoatNormalTransformOffsetScale
        0.0f                                  // clearcoatNormalTransformRotation
    };
}
