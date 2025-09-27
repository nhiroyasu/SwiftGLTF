import Foundation

public enum MaterialPropertyName: String {
    case normalTexture
    case baseColorFactor
    case baseColorTexture
    case metallic
    case roughness
    case metallicRoughnessTexture
    case emissiveFactor
    case emissiveTexture
    case occlusion
    case occlusionStrength
    case alphaMode
    case alphaCutoff
    // Mesh center (from POSITION min/max)
    case meshCenter
    // Texture coordinate indices for UV sets
    case normalTextureTexCoord
    case baseColorTextureTexCoord
    case metallicRoughnessTextureTexCoord
    case emissiveTextureTexCoord
    case occlusionTextureTexCoord
    case doubleSided
    // Transmission (KHR_materials_transmission)
    case transmissionFactor
    case transmissionTexture
    case transmissionTextureTexCoord
    // Volume (KHR_materials_volume)
    case thicknessFactor
    case thicknessTexture
    case thicknessTextureTexCoord
    case attenuationDistance
    case attenuationColor
    case ior
    // Specular (KHR_materials_specular)
    case specularFactor
    case specularTexture
    case specularTextureTexCoord
    case specularColorFactor
    case specularColorTexture
    case specularColorTextureTexCoord
    // Sheen (KHR_materials_sheen)
    case sheenColorFactor
    case sheenColorTexture
    case sheenColorTextureTexCoord
    case sheenRoughnessFactor
    case sheenRoughnessTexture
    case sheenRoughnessTextureTexCoord
}
