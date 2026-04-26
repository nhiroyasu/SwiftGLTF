import Foundation

public enum MaterialPropertyName: String {
    case normalTexture
    case baseColorFactor
    case baseColorTexture
    case metallic
    case roughness
    case metallicRoughnessTexture
    case emissiveFactor
    case emissiveStrength
    case emissiveTexture
    case occlusion
    case occlusionStrength
    case alphaMode
    case alphaCutoff
    // Texture coordinate indices for UV sets
    case normalTextureTexCoord
    case normalTextureTransformOffsetScale
    case normalTextureTransformRotation
    case baseColorTextureTexCoord
    case baseColorTextureTransformOffsetScale
    case baseColorTextureTransformRotation
    case metallicRoughnessTextureTexCoord
    case metallicRoughnessTextureTransformOffsetScale
    case metallicRoughnessTextureTransformRotation
    case emissiveTextureTexCoord
    case emissiveTextureTransformOffsetScale
    case emissiveTextureTransformRotation
    case occlusionTextureTexCoord
    case occlusionTextureTransformOffsetScale
    case occlusionTextureTransformRotation
    case doubleSided
    case unlit
    // Transmission (KHR_materials_transmission)
    case transmissionFactor
    case transmissionTexture
    case transmissionTextureTexCoord
    case transmissionTextureTransformOffsetScale
    case transmissionTextureTransformRotation
    // Volume (KHR_materials_volume)
    case thicknessFactor
    case thicknessTexture
    case thicknessTextureTexCoord
    case thicknessTextureTransformOffsetScale
    case thicknessTextureTransformRotation
    case attenuationDistance
    case attenuationColor
    case ior
    // Clearcoat (KHR_materials_clearcoat)
    case clearcoatFactor
    case clearcoatTexture
    case clearcoatTextureTexCoord
    case clearcoatTextureTransformOffsetScale
    case clearcoatTextureTransformRotation
    case clearcoatRoughnessFactor
    case clearcoatRoughnessTexture
    case clearcoatRoughnessTextureTexCoord
    case clearcoatRoughnessTextureTransformOffsetScale
    case clearcoatRoughnessTextureTransformRotation
    case clearcoatNormalTexture
    case clearcoatNormalTextureTexCoord
    case clearcoatNormalTextureTransformOffsetScale
    case clearcoatNormalTextureTransformRotation
    case clearcoatNormalTextureScale
    // Specular (KHR_materials_specular)
    case specularFactor
    case specularTexture
    case specularTextureTexCoord
    case specularTextureTransformOffsetScale
    case specularTextureTransformRotation
    case specularColorFactor
    case specularColorTexture
    case specularColorTextureTexCoord
    case specularColorTextureTransformOffsetScale
    case specularColorTextureTransformRotation
    // Sheen (KHR_materials_sheen)
    case sheenColorFactor
    case sheenColorTexture
    case sheenColorTextureTexCoord
    case sheenColorTextureTransformOffsetScale
    case sheenColorTextureTransformRotation
    case sheenRoughnessFactor
    case sheenRoughnessTexture
    case sheenRoughnessTextureTexCoord
    case sheenRoughnessTextureTransformOffsetScale
    case sheenRoughnessTextureTransformRotation
}
