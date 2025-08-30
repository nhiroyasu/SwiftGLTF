import Foundation
import ModelIO

public struct GLTFContainer {
    public let gltf: GLTF
    /// Embedded binary chunks; for .glb files this contains the BIN chunk data
    public let binaryBuffers: [Data]
    /// Image binary data mapped by image index (embedded or external)
    public let binaryTextures: [MDLTexture]

    public init(gltf: GLTF, binaryBuffers: [Data], binaryTextures: [MDLTexture]) {
        self.gltf = gltf
        self.binaryBuffers = binaryBuffers
        self.binaryTextures = binaryTextures
    }
}

public struct GLTF: Codable {
    public let asset: Asset
    public let buffers: [Buffer]?
    public let bufferViews: [BufferView]?
    public let accessors: [Accessor]?
    public let meshes: [Mesh]?
    public let scenes: [Scene]?
    public let scene: Int? // spec: default undefined
    public let nodes: [Node]?
    public let skins: [Skin]?
    public let animations: [Animation]?
    public let materials: [Material]?
    public let images: [Image]?
    public let textures: [Texture]?
    public let samplers: [Sampler]?

    enum CodingKeys: String, CodingKey {
        case asset
        case buffers
        case bufferViews
        case accessors
        case meshes
        case scenes
        case scene
        case nodes
        case skins
        case animations
        case materials
        case images
        case textures
        case samplers
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.asset = try container.decode(Asset.self, forKey: .asset)
        self.buffers = try container.decodeIfPresent([Buffer].self, forKey: .buffers)
        self.bufferViews = try container.decodeIfPresent([BufferView].self, forKey: .bufferViews)
        self.accessors = try container.decodeIfPresent([Accessor].self, forKey: .accessors)
        self.meshes = try container.decodeIfPresent([Mesh].self, forKey: .meshes)
        self.scenes = try container.decodeIfPresent([Scene].self, forKey: .scenes)
        self.scene = try container.decodeIfPresent(Int.self, forKey: .scene)
        self.nodes = try container.decodeIfPresent([Node].self, forKey: .nodes)
        self.skins = try container.decodeIfPresent([Skin].self, forKey: .skins)
        self.animations = try container.decodeIfPresent([Animation].self, forKey: .animations)
        self.materials = try container.decodeIfPresent([Material].self, forKey: .materials)
        self.images = try container.decodeIfPresent([Image].self, forKey: .images)
        self.textures = try container.decodeIfPresent([Texture].self, forKey: .textures)
        self.samplers = try container.decodeIfPresent([Sampler].self, forKey: .samplers)
    }
}

public struct Scene: Codable {
    public let name: String?
    public let nodes: [Int]?
}

public struct Material: Codable {
    public let name: String?
    public let pbrMetallicRoughness: PBRMetallicRoughness?
    public let normalTexture: NormalTextureInfo?
    public let occlusionTexture: OcclusionTextureInfo?
    public let emissiveTexture: TextureInfo?
    public let emissiveFactor: [Float]
    public let alphaMode: AlphaMode
    public let alphaCutoff: Float
    /// If true, back-face culling is disabled. Defaults to false.
    public let doubleSided: Bool
    /// Optional glTF extensions for Material
    public let extensions: MaterialExtensions?

    enum CodingKeys: String, CodingKey {
        case name
        case pbrMetallicRoughness
        case normalTexture
        case occlusionTexture
        case emissiveTexture
        case emissiveFactor
        case alphaMode
        case alphaCutoff
        case doubleSided
        case extensions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.pbrMetallicRoughness = try container.decodeIfPresent(PBRMetallicRoughness.self, forKey: .pbrMetallicRoughness)
        self.normalTexture = try container.decodeIfPresent(NormalTextureInfo.self, forKey: .normalTexture)
        self.occlusionTexture = try container.decodeIfPresent(OcclusionTextureInfo.self, forKey: .occlusionTexture)
        self.emissiveTexture = try container.decodeIfPresent(TextureInfo.self, forKey: .emissiveTexture)
        self.emissiveFactor = try container.decodeIfPresent([Float].self, forKey: .emissiveFactor) ?? [0, 0, 0]
        self.alphaMode = try container.decodeIfPresent(AlphaMode.self, forKey: .alphaMode) ?? .opaque
        self.alphaCutoff = try container.decodeIfPresent(Float.self, forKey: .alphaCutoff) ?? 0.5
        self.doubleSided = try container.decodeIfPresent(Bool.self, forKey: .doubleSided) ?? false
        self.extensions = try container.decodeIfPresent(MaterialExtensions.self, forKey: .extensions)
    }
}

public struct PBRMetallicRoughness: Codable {
    public let baseColorFactor: [Float]
    public let baseColorTexture: TextureInfo?
    public let metallicFactor: Float
    public let roughnessFactor: Float
    public let metallicRoughnessTexture: TextureInfo?

    enum CodingKeys: String, CodingKey {
        case baseColorFactor
        case baseColorTexture
        case metallicFactor
        case roughnessFactor
        case metallicRoughnessTexture
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.baseColorFactor = try container.decodeIfPresent([Float].self, forKey: .baseColorFactor) ?? [1, 1, 1, 1]
        self.baseColorTexture = try container.decodeIfPresent(TextureInfo.self, forKey: .baseColorTexture)
        self.metallicFactor = try container.decodeIfPresent(Float.self, forKey: .metallicFactor) ?? 1.0
        self.roughnessFactor = try container.decodeIfPresent(Float.self, forKey: .roughnessFactor) ?? 1.0
        self.metallicRoughnessTexture = try container.decodeIfPresent(TextureInfo.self, forKey: .metallicRoughnessTexture)
    }
}

public struct TextureIndex: Codable, Hashable, ExpressibleByIntegerLiteral {
    public let value: Int

    public init(_ value: Int) {
        self.value = value
    }

    public init(integerLiteral value: Int) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try container.decode(Int.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

public struct AccessorIndex: Codable, Hashable, ExpressibleByIntegerLiteral {
    public let value: Int

    public init(_ value: Int) {
        self.value = value
    }

    public init(integerLiteral value: Int) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try container.decode(Int.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

public struct TextureInfo: Codable {
    public let index: TextureIndex
    public let texCoord: Int

    enum CodingKeys: String, CodingKey {
        case index
        case texCoord
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.index = try container.decode(TextureIndex.self, forKey: .index)
        self.texCoord = try container.decodeIfPresent(Int.self, forKey: .texCoord) ?? 0
    }
}

public struct NormalTextureInfo: Codable {
    public let index: TextureIndex
    public let texCoord: Int
    public let scale: Float

    enum CodingKeys: String, CodingKey {
        case index
        case texCoord
        case scale
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.index = try container.decode(TextureIndex.self, forKey: .index)
        self.texCoord = try container.decodeIfPresent(Int.self, forKey: .texCoord) ?? 0
        self.scale = try container.decodeIfPresent(Float.self, forKey: .scale) ?? 1.0
    }
}

public struct OcclusionTextureInfo: Codable {
    public let index: TextureIndex
    public let texCoord: Int
    public let strength: Float

    enum CodingKeys: String, CodingKey {
        case index
        case texCoord
        case strength
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.index = try container.decode(TextureIndex.self, forKey: .index)
        self.texCoord = try container.decodeIfPresent(Int.self, forKey: .texCoord) ?? 0
        self.strength = try container.decodeIfPresent(Float.self, forKey: .strength) ?? 1.0
    }
}

public struct Node: Codable {
    public let name: String?
    public let mesh: MeshIndex?
    public let skin: SkinIndex?
    /// Morph target weights for this node (applied per mesh instance)
    /// glTF: node.weights
    public let weights: [Float]?
    public let children: [Int]?
    public let translation: [Float]?
    public let rotation: [Float]?
    public let scale: [Float]?
    public let matrix: [Float]?

    public init(name: String?, mesh: MeshIndex?, skin: SkinIndex?, weights: [Float]?, children: [Int]?, translation: [Float]?, rotation: [Float]?, scale: [Float]?, matrix: [Float]?) {
        self.name = name
        self.mesh = mesh
        self.skin = skin
        self.weights = weights
        self.children = children
        self.translation = translation
        self.rotation = rotation
        self.scale = scale
        self.matrix = matrix
    }
}

public struct NodeIndex: Codable, Hashable, ExpressibleByIntegerLiteral {
    public let value: Int

    public init(_ value: Int) {
        self.value = value
    }

    public init(integerLiteral value: Int) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try container.decode(Int.self)
    }
}

public struct Asset: Codable {
    public let version: String
    public let generator: String?
}

public struct Buffer: Codable {
    public let uri: String?
    public let byteLength: Int
}

public struct BufferIndex: Codable, Hashable, ExpressibleByIntegerLiteral {
    public let value: Int

    public init(_ value: Int) {
        self.value = value
    }

    public init(integerLiteral value: Int) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try container.decode(Int.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

public struct BufferView: Codable {
    public let buffer: BufferIndex
    public let byteOffset: Int
    public let byteLength: Int
    public let byteStride: Int?
    public let target: Int?

    enum CodingKeys: String, CodingKey {
        case buffer
        case byteOffset
        case byteLength
        case byteStride
        case target
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.buffer = try container.decode(BufferIndex.self, forKey: .buffer)
        self.byteOffset = try container.decodeIfPresent(Int.self, forKey: .byteOffset) ?? 0
        self.byteLength = try container.decode(Int.self, forKey: .byteLength)
        self.byteStride = try container.decodeIfPresent(Int.self, forKey: .byteStride)
        self.target = try container.decodeIfPresent(Int.self, forKey: .target)
    }
}

public struct BufferViewIndex: Codable, Hashable, ExpressibleByIntegerLiteral {
    public let value: Int

    public init(_ value: Int) {
        self.value = value
    }

    public init(integerLiteral value: Int) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try container.decode(Int.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

public struct Accessor: Codable {
    public let bufferView: BufferViewIndex?
    public let byteOffset: Int
    public let componentType: GLTFComponentType
    public let count: Int
    public let type: GLTFDataType
    public let max: [Float]?
    public let min: [Float]?
    /// If true, integer data values should be normalized to [0,1] (unsigned) or [-1,1] (signed)
    /// For WEIGHTS_0, this allows decoding ubyte4/ushort4 as float4 via normalization.
    public let normalized: Bool

    enum CodingKeys: String, CodingKey {
        case bufferView
        case byteOffset
        case componentType
        case count
        case type
        case max
        case min
        case normalized
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.bufferView = try container.decodeIfPresent(BufferViewIndex.self, forKey: .bufferView)
        self.byteOffset = try container.decodeIfPresent(Int.self, forKey: .byteOffset) ?? 0
        self.componentType = try container.decode(GLTFComponentType.self, forKey: .componentType)
        self.count = try container.decode(Int.self, forKey: .count)
        self.type = try container.decode(GLTFDataType.self, forKey: .type)
        self.max = try container.decodeIfPresent([Float].self, forKey: .max)
        self.min = try container.decodeIfPresent([Float].self, forKey: .min)
        self.normalized = try container.decodeIfPresent(Bool.self, forKey: .normalized) ?? false
    }
}

public struct Skin: Codable {
    public let name: String?
    public let inverseBindMatrices: AccessorIndex?
    /// Skeleton root node index
    public let skeleton: Int?
    /// Joint node indices
    public let joints: [NodeIndex]
}

public struct SkinIndex: Codable, Hashable, ExpressibleByIntegerLiteral {
    public let value: Int

    public init(_ value: Int) {
        self.value = value
    }

    public init(integerLiteral value: Int) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try container.decode(Int.self)
    }
}

public struct Mesh: Codable {
    public let name: String?
    public let primitives: [Primitive]
    /// Default morph target weights for this mesh
    /// glTF: mesh.weights
    public let weights: [Float]?
}

public struct MeshIndex: Codable, Hashable, ExpressibleByIntegerLiteral {
    public let value: Int

    public init(_ value: Int) {
        self.value = value
    }

    public init(integerLiteral value: Int) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try container.decode(Int.self)
    }
}

public struct Primitive: Codable {
    public let attributes: [String: Int]
    public let indices: AccessorIndex?
    public let material: Int?
    public let mode: GLTFPrimitiveMode
    /// Morph targets: Each element is a map from attribute name (e.g. "POSITION") to accessor index
    /// glTF: mesh.primitives[*].targets
    public let targets: [[String: Int]]?

    enum CodingKeys: String, CodingKey {
        case attributes
        case indices
        case material
        case mode
        case targets
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.attributes = try container.decode([String: Int].self, forKey: .attributes)
        self.indices = try container.decodeIfPresent(AccessorIndex.self, forKey: .indices)
        self.material = try container.decodeIfPresent(Int.self, forKey: .material)
        self.mode = try container.decodeIfPresent(GLTFPrimitiveMode.self, forKey: .mode) ?? .triangles
        self.targets = try container.decodeIfPresent([[String: Int]].self, forKey: .targets)
    }
}

public struct Image: Codable {
    public let uri: String?
    public let mimeType: String?
    public let bufferView: BufferViewIndex?
    public let name: String?
}

public struct ImageIndex: Codable, Hashable, ExpressibleByIntegerLiteral {
    public let value: Int

    public init(_ value: Int) {
        self.value = value
    }

    public init(integerLiteral value: Int) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try container.decode(Int.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

public struct Texture: Codable {
    public let sampler: Int?
    public let source: ImageIndex?
    public let name: String?
}

public struct Sampler: Codable {
    public let magFilter: GLTFFilterMode?
    public let minFilter: GLTFFilterMode?
    public let wrapS: GLTFWrapMode
    public let wrapT: GLTFWrapMode
    public let name: String?

    enum CodingKeys: String, CodingKey {
        case magFilter
        case minFilter
        case wrapS
        case wrapT
        case name
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.magFilter = try container.decodeIfPresent(GLTFFilterMode.self, forKey: .magFilter)
        self.minFilter = try container.decodeIfPresent(GLTFFilterMode.self, forKey: .minFilter)
        self.wrapS = try container.decodeIfPresent(GLTFWrapMode.self, forKey: .wrapS) ?? .repeatWrap
        self.wrapT = try container.decodeIfPresent(GLTFWrapMode.self, forKey: .wrapT) ?? .repeatWrap
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
    }
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

// MARK: - Animations

/// Animation clip
public struct Animation: Codable {
    public let name: String?
    public let samplers: [AnimationSampler]
    public let channels: [AnimationChannel]
}

/// Animation sampler mapping input times to output values
public struct AnimationSampler: Codable {
    public let input: AccessorIndex
    public let output: AccessorIndex
    public let interpolation: GLTFInterpolation

    enum CodingKeys: String, CodingKey {
        case input
        case output
        case interpolation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.input = try container.decode(AccessorIndex.self, forKey: .input)
        self.output = try container.decode(AccessorIndex.self, forKey: .output)
        self.interpolation = try container.decodeIfPresent(GLTFInterpolation.self, forKey: .interpolation) ?? .linear
    }
}

/// Animation channel targeting a node path
public struct AnimationChannel: Codable {
    public struct Target: Codable {
        public let node: NodeIndex?
        public let path: AnimationPath
    }

    public let sampler: Int
    public let target: Target
}

/// Path for animation target
public enum AnimationPath: String, Codable {
    case translation
    case rotation
    case scale
    case weights
    case unknown

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = AnimationPath(rawValue: rawValue) ?? .unknown
    }
}

/// Interpolation type for animation sampler
public enum GLTFInterpolation: String, Codable {
    case linear = "LINEAR"
    case step = "STEP"
    case cubicSpline = "CUBICSPLINE"
}

// MARK: - KHR_materials_emissive_strength extension
/// glTF extension KHR_materials_emissive_strength provides a multiplier for emissive color and textures.
public struct KHRMaterialsEmissiveStrength: Codable {
    /// The emissive strength multiplier. Defaults to 1.0 if not specified.
    public let emissiveStrength: Float
    enum CodingKeys: String, CodingKey {
        case emissiveStrength = "emissiveStrength"
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.emissiveStrength = try container.decodeIfPresent(Float.self, forKey: .emissiveStrength) ?? 1.0
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

// MARK: - AlphaMode (glTF Material.alphaMode)
public enum AlphaMode: String, Codable {
    case opaque = "OPAQUE"
    case mask = "MASK"
    case blend = "BLEND"
}
