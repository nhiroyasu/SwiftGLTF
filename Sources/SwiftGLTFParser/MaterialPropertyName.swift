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
    // Texture coordinate indices for UV sets
    case normalTextureTexCoord
    case baseColorTextureTexCoord
    case metallicRoughnessTextureTexCoord
    case emissiveTextureTexCoord
    case occlusionTextureTexCoord
}
