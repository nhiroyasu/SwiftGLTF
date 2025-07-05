import Foundation
import ModelIO

public struct GLTF: Codable {
    public let asset: Asset
    public let buffers: [Buffer]?
    public let bufferViews: [BufferView]?
    public let accessors: [Accessor]?
    public let meshes: [Mesh]?
    public let scenes: [Scene]?
    public let scene: Int?
    public let nodes: [Node]?
    public let materials: [Material]?
    public let images: [Image]?
    public let textures: [Texture]?
    public let samplers: [Sampler]?
}

public struct Scene: Codable {
    public let name: String?
    public let nodes: [Int]?
}

public struct Material: Codable {
    public let name: String?
    public let pbrMetallicRoughness: PBRMetallicRoughness?
    public let normalTexture: TextureInfo?
    public let occlusionTexture: TextureInfo?
    public let emissiveTexture: TextureInfo?
    public let emissiveFactor: [Float]?
    public let alphaMode: String?
    public let alphaCutoff: Float?
    public let doubleSided: Bool?
    /// Optional glTF extensions for Material
    public let extensions: MaterialExtensions?
}

public struct PBRMetallicRoughness: Codable {
    public let baseColorFactor: [Float]?
    public let baseColorTexture: TextureInfo?
    public let metallicFactor: Float?
    public let roughnessFactor: Float?
    public let metallicRoughnessTexture: TextureInfo?
}

public struct TextureInfo: Codable {
    public let index: Int
    public let texCoord: Int?
}

public struct Node: Codable {
    public let name: String?
    public let mesh: Int?
    public let children: [Int]?
    public let translation: [Float]?
    public let rotation: [Float]?
    public let scale: [Float]?
    public let matrix: [Float]?
}

public struct Asset: Codable {
    public let version: String
    public let generator: String?
}

public struct Buffer: Codable {
    public let uri: String?
    public let byteLength: Int
}

public struct BufferView: Codable {
    public let buffer: Int
    public let byteOffset: Int?
    public let byteLength: Int
    public let byteStride: Int?
    public let target: Int?
}

public struct Accessor: Codable {
    public let bufferView: Int?
    public let byteOffset: Int?
    public let componentType: GLTFComponentType
    public let count: Int
    public let type: GLTFDataType
    public let max: [Float]?
    public let min: [Float]?
}

public struct Mesh: Codable {
    public let primitives: [Primitive]
}

public struct Primitive: Codable {
    public let attributes: [String: Int]
    public let indices: Int?
    public let material: Int?
    public let mode: GLTFPrimitiveMode?
}

public struct Image: Codable {
    public let uri: String?
    public let mimeType: String?
    public let bufferView: Int?
    public let name: String?
}

public struct Texture: Codable {
    public let sampler: Int?
    public let source: Int?
    public let name: String?
}

public struct Sampler: Codable {
    public let magFilter: GLTFFilterMode?
    public let minFilter: GLTFFilterMode?
    public let wrapS: GLTFWrapMode?
    public let wrapT: GLTFWrapMode?
    public let name: String?
}

// MARK: - glTF-specific values

// componentType の値を表す enum
// en: Enum representing the values of componentType
public enum GLTFComponentType: Int, RawRepresentable, Codable {
    case byte = 5120
    case unsignedByte = 5121
    case short = 5122
    case unsignedShort = 5123
    case unsignedInt = 5125
    case float = 5126

    public var size: Int {
        switch self {
        case .byte, .unsignedByte: return 1
        case .short, .unsignedShort: return 2
        case .unsignedInt, .float: return 4
        }
    }
}

// 頂点属性のキーを表す enum
// en: Enum representing attribute keys
public enum GLTFAttribute: RawRepresentable, Decodable {
    case position
    case normal
    case tangent
    case texcoord(_ index: Int)
    case color(_ index: Int)
    // 必要に応じて他の属性も追加可能
    // en: Additional attributes can be added as needed

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let key = try container.decode(String.self)

        switch key {
        case "POSITION":
            self = .position
        case "NORMAL":
            self = .normal
        case "TANGENT":
            self = .tangent
        default:
            if key.hasPrefix("TEXCOORD_") {
                if let index = Int(key.dropFirst("TEXCOORD_".count)) {
                    self = .texcoord(index)
                } else {
                    throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid TEXCOORD format")
                }
            } else if key.hasPrefix("COLOR_") {
                if let index = Int(key.dropFirst("COLOR_".count)) {
                    self = .color(index)
                } else {
                    throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid COLOR format")
                }
            } else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown attribute key: \(key)")
            }
        }
    }

    // MARK: - RawRepresentable

    public typealias RawValue = String

    public init?(rawValue: String) {
        switch rawValue {
        case "POSITION":
            self = .position
        case "NORMAL":
            self = .normal
        case "TANGENT":
            self = .tangent
        default:
            if rawValue.hasPrefix("TEXCOORD_") {
                if let index = Int(rawValue.dropFirst("TEXCOORD_".count)) {
                    self = .texcoord(index)
                } else {
                    return nil
                }
            } else if rawValue.hasPrefix("COLOR_") {
                if let index = Int(rawValue.dropFirst("COLOR_".count)) {
                    self = .color(index)
                } else {
                    return nil
                }
            } else {
                return nil
            }
        }
    }

    public var rawValue: String {
        switch self {
        case .position: return "POSITION"
        case .normal: return "NORMAL"
        case .tangent: return "TANGENT"
        case .texcoord(let index): return "TEXCOORD_\(index)"
        case .color(let index): return "COLOR_\(index)"
        }
    }

    // MARK: - Static

    public static let texCoordPrefix = "TEXCOORD_"
    public static let colorPrefix = "COLOR_"
}

// Data type for accessor.type ("SCALAR", "VEC2", etc.)
public enum GLTFDataType: String, RawRepresentable, Codable {
    case scalar = "SCALAR"
    case vec2 = "VEC2"
    case vec3 = "VEC3"
    case vec4 = "VEC4"
    case mat2 = "MAT2"
    case mat3 = "MAT3"
    case mat4 = "MAT4"

    public var components: Int {
        switch self {
        case .scalar: return 1
        case .vec2: return 2
        case .vec3: return 3
        case .vec4: return 4
        case .mat2: return 4
        case .mat3: return 9
        case .mat4: return 16
        }
    }
}

public enum GLTFFilterMode: Int, Codable {
    case nearest = 9728           // NEAREST
    case linear = 9729            // LINEAR
    case nearestMipmapNearest = 9984
    case linearMipmapNearest = 9985
    case nearestMipmapLinear = 9986
    case linearMipmapLinear = 9987
}

public enum GLTFWrapMode: Int, Codable {
    case clampToEdge = 33071       // CLAMP_TO_EDGE
    case mirroredRepeat = 33648    // MIRRORED_REPEAT
    case repeatWrap = 10497        // REPEAT
}

public enum GLTFPrimitiveMode: Int, Codable {
    case points = 0              // POINTS
    case lines = 1               // LINES
    case lineLoop = 2            // LINE_LOOP
    case lineStrip = 3           // LINE_STRIP
    case triangles = 4           // TRIANGLES
    case triangleStrip = 5       // TRIANGLE_STRIP
    case triangleFan = 6         // TRIANGLE_FAN
}
// MARK: - KHR_materials_emissive_strength extension
/// glTF extension KHR_materials_emissive_strength provides a multiplier for emissive color and textures.
public struct KHRMaterialsEmissiveStrength: Codable {
    /// The emissive strength multiplier. Defaults to 1.0 if not specified.
    public let emissiveStrength: Float
    enum CodingKeys: String, CodingKey {
        case emissiveStrength = "emissiveStrength"
    }
}

/// Container for material-specific extensions
public struct MaterialExtensions: Codable {
    /// KHR_materials_emissive_strength extension data
    public let khrMaterialsEmissiveStrength: KHRMaterialsEmissiveStrength?
    enum CodingKeys: String, CodingKey {
        case khrMaterialsEmissiveStrength = "KHR_materials_emissive_strength"
    }
}
