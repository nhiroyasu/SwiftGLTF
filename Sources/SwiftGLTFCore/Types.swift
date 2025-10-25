import Foundation
import ModelIO

public struct GLTFBundle: Equatable {
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

public struct GLTF: Codable, Equatable {
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
    public let extensionsUsed: [String]?
    public let extensionsRequired: [String]?

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
        case extensionsUsed
        case extensionsRequired
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
        self.extensionsUsed = try container.decodeIfPresent([String].self, forKey: .extensionsUsed)
        self.extensionsRequired = try container.decodeIfPresent([String].self, forKey: .extensionsRequired)
    }
}

public struct Scene: Codable, Equatable {
    public let name: String?
    public let nodes: [Int]?
}

public struct Material: Codable, Equatable {
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

public struct PBRMetallicRoughness: Codable, Equatable {
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

public struct TextureIndex: Codable, Hashable, ExpressibleByIntegerLiteral, Equatable {
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

public struct AccessorIndex: Codable, Hashable, ExpressibleByIntegerLiteral, Equatable {
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

public struct KHRTextureTransform: Codable, Equatable {
    public let offset: [Float]
    public let rotation: Float
    public let scale: [Float]
    public let texCoord: Int?

    enum CodingKeys: String, CodingKey {
        case offset
        case rotation
        case scale
        case texCoord
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let offsetValue = try container.decodeIfPresent([Float].self, forKey: .offset) ?? [0, 0]
        let scaleValue = try container.decodeIfPresent([Float].self, forKey: .scale) ?? [1, 1]
        self.offset = [
            offsetValue.count > 0 ? offsetValue[0] : 0,
            offsetValue.count > 1 ? offsetValue[1] : 0
        ]
        self.rotation = try container.decodeIfPresent(Float.self, forKey: .rotation) ?? 0
        self.scale = [
            scaleValue.count > 0 ? scaleValue[0] : 1,
            scaleValue.count > 1 ? scaleValue[1] : 1
        ]
        self.texCoord = try container.decodeIfPresent(Int.self, forKey: .texCoord)
    }
}

public struct TextureInfoExtensions: Codable, Equatable {
    public let khrTextureTransform: KHRTextureTransform?

    enum CodingKeys: String, CodingKey {
        case khrTextureTransform = "KHR_texture_transform"
    }
}

public struct TextureInfo: Codable, Equatable {
    public let index: TextureIndex
    public let texCoord: Int
    public let extensions: TextureInfoExtensions?

    enum CodingKeys: String, CodingKey {
        case index
        case texCoord
        case extensions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.index = try container.decode(TextureIndex.self, forKey: .index)
        self.texCoord = try container.decodeIfPresent(Int.self, forKey: .texCoord) ?? 0
        self.extensions = try container.decodeIfPresent(TextureInfoExtensions.self, forKey: .extensions)
    }
}

public struct NormalTextureInfo: Codable, Equatable {
    public let index: TextureIndex
    public let texCoord: Int
    public let scale: Float
    public let extensions: TextureInfoExtensions?

    enum CodingKeys: String, CodingKey {
        case index
        case texCoord
        case scale
        case extensions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.index = try container.decode(TextureIndex.self, forKey: .index)
        self.texCoord = try container.decodeIfPresent(Int.self, forKey: .texCoord) ?? 0
        self.scale = try container.decodeIfPresent(Float.self, forKey: .scale) ?? 1.0
        self.extensions = try container.decodeIfPresent(TextureInfoExtensions.self, forKey: .extensions)
    }
}

public struct OcclusionTextureInfo: Codable, Equatable {
    public let index: TextureIndex
    public let texCoord: Int
    public let strength: Float
    public let extensions: TextureInfoExtensions?

    enum CodingKeys: String, CodingKey {
        case index
        case texCoord
        case strength
        case extensions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.index = try container.decode(TextureIndex.self, forKey: .index)
        self.texCoord = try container.decodeIfPresent(Int.self, forKey: .texCoord) ?? 0
        self.strength = try container.decodeIfPresent(Float.self, forKey: .strength) ?? 1.0
        self.extensions = try container.decodeIfPresent(TextureInfoExtensions.self, forKey: .extensions)
    }
}

public extension TextureInfo {
    var textureTransform: KHRTextureTransform? {
        extensions?.khrTextureTransform
    }

    var effectiveTexCoord: Int {
        textureTransform?.texCoord ?? texCoord
    }
}

public extension NormalTextureInfo {
    var textureTransform: KHRTextureTransform? {
        extensions?.khrTextureTransform
    }

    var effectiveTexCoord: Int {
        textureTransform?.texCoord ?? texCoord
    }
}

public extension OcclusionTextureInfo {
    var textureTransform: KHRTextureTransform? {
        extensions?.khrTextureTransform
    }

    var effectiveTexCoord: Int {
        textureTransform?.texCoord ?? texCoord
    }
}

public struct Node: Codable, Equatable {
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

public struct NodeIndex: Codable, Hashable, ExpressibleByIntegerLiteral, Equatable {
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

public struct Asset: Codable, Equatable {
    public let version: String
    public let generator: String?
}

public struct Buffer: Codable, Equatable {
    public let uri: String?
    public let byteLength: Int
}

public struct BufferIndex: Codable, Hashable, ExpressibleByIntegerLiteral, Equatable {
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

public struct BufferView: Codable, Equatable {
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

public struct BufferViewIndex: Codable, Hashable, ExpressibleByIntegerLiteral, Equatable {
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

public struct Accessor: Codable, Equatable {
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

public struct Skin: Codable, Equatable {
    public let name: String?
    public let inverseBindMatrices: AccessorIndex?
    /// Skeleton root node index
    public let skeleton: Int?
    /// Joint node indices
    public let joints: [NodeIndex]
}

public struct SkinIndex: Codable, Hashable, ExpressibleByIntegerLiteral, Equatable {
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

public struct Mesh: Codable, Equatable {
    public let name: String?
    public let primitives: [Primitive]
    /// Default morph target weights for this mesh
    /// glTF: mesh.weights
    public let weights: [Float]?
}

public struct MeshIndex: Codable, Hashable, ExpressibleByIntegerLiteral, Equatable {
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

public struct Primitive: Codable, Equatable {
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

public struct Image: Codable, Equatable {
    public let uri: String?
    public let mimeType: String?
    public let bufferView: BufferViewIndex?
    public let name: String?
}

public struct ImageIndex: Codable, Hashable, ExpressibleByIntegerLiteral, Equatable {
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

public struct Texture: Codable, Equatable {
    public let sampler: Int?
    public let source: ImageIndex?
    public let name: String?
}

public struct Sampler: Codable, Equatable {
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
public enum GLTFComponentType: Int, RawRepresentable, Codable, Equatable {
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
public enum GLTFAttribute: RawRepresentable, Decodable, Equatable {
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
public enum GLTFDataType: String, RawRepresentable, Codable, Equatable {
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

public enum GLTFFilterMode: Int, Codable, Equatable {
    case nearest = 9728           // NEAREST
    case linear = 9729            // LINEAR
    case nearestMipmapNearest = 9984
    case linearMipmapNearest = 9985
    case nearestMipmapLinear = 9986
    case linearMipmapLinear = 9987
}

public enum GLTFWrapMode: Int, Codable, Equatable {
    case clampToEdge = 33071       // CLAMP_TO_EDGE
    case mirroredRepeat = 33648    // MIRRORED_REPEAT
    case repeatWrap = 10497        // REPEAT
}

public enum GLTFPrimitiveMode: Int, Codable, Equatable {
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
public struct Animation: Codable, Equatable {
    public let name: String?
    public let samplers: [AnimationSampler]
    public let channels: [AnimationChannel]
}

/// Animation sampler mapping input times to output values
public struct AnimationSampler: Codable, Equatable {
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
public struct AnimationChannel: Codable, Equatable {
    public struct Target: Codable, Equatable {
        public let node: NodeIndex?
        public let path: AnimationPath
    }

    public let sampler: Int
    public let target: Target
}

/// Path for animation target
public enum AnimationPath: String, Codable, Equatable {
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
public enum GLTFInterpolation: String, Codable, Equatable {
    case linear = "LINEAR"
    case step = "STEP"
    case cubicSpline = "CUBICSPLINE"
}

// MARK: - KHR_materials_emissive_strength extension
/// glTF extension KHR_materials_emissive_strength provides a multiplier for emissive color and textures.
public struct KHRMaterialsEmissiveStrength: Codable, Equatable {
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
public struct MaterialExtensions: Codable, Equatable {
    /// KHR_materials_emissive_strength extension data
    public let khrMaterialsEmissiveStrength: KHRMaterialsEmissiveStrength?
    /// KHR_materials_transmission extension data
    public let khrMaterialsTransmission: KHRMaterialsTransmission?
    /// KHR_materials_volume extension data
    public let khrMaterialsVolume: KHRMaterialsVolume?
    /// KHR_materials_ior extension data
    public let khrMaterialsIOR: KHRMaterialsIOR?
    /// KHR_materials_clearcoat extension data
    public let khrMaterialsClearcoat: KHRMaterialsClearcoat?
    /// KHR_materials_specular extension data
    public let khrMaterialsSpecular: KHRMaterialsSpecular?
    /// KHR_materials_sheen extension data
    public let khrMaterialsSheen: KHRMaterialsSheen?
    enum CodingKeys: String, CodingKey {
        case khrMaterialsEmissiveStrength = "KHR_materials_emissive_strength"
        case khrMaterialsTransmission = "KHR_materials_transmission"
        case khrMaterialsVolume = "KHR_materials_volume"
        case khrMaterialsIOR = "KHR_materials_ior"
        case khrMaterialsClearcoat = "KHR_materials_clearcoat"
        case khrMaterialsSpecular = "KHR_materials_specular"
        case khrMaterialsSheen = "KHR_materials_sheen"
    }
}

// MARK: - AlphaMode (glTF Material.alphaMode)
public enum AlphaMode: String, Codable, Equatable {
    case opaque = "OPAQUE"
    case mask = "MASK"
    case blend = "BLEND"
}

// MARK: - KHR_materials_transmission extension
public struct KHRMaterialsTransmission: Codable, Equatable {
    public let transmissionFactor: Float
    public let transmissionTexture: TextureInfo?
    enum CodingKeys: String, CodingKey {
        case transmissionFactor
        case transmissionTexture
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.transmissionFactor = try container.decodeIfPresent(Float.self, forKey: .transmissionFactor) ?? 0.0
        self.transmissionTexture = try container.decodeIfPresent(TextureInfo.self, forKey: .transmissionTexture)
    }
}

// MARK: - KHR_materials_volume extension
public struct KHRMaterialsVolume: Codable, Equatable {
    public let thicknessFactor: Float
    public let thicknessTexture: TextureInfo?
    public let attenuationDistance: Float?
    public let attenuationColor: [Float]
    enum CodingKeys: String, CodingKey {
        case thicknessFactor
        case thicknessTexture
        case attenuationDistance
        case attenuationColor
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.thicknessFactor = try container.decodeIfPresent(Float.self, forKey: .thicknessFactor) ?? 0.0
        self.thicknessTexture = try container.decodeIfPresent(TextureInfo.self, forKey: .thicknessTexture)
        self.attenuationDistance = try container.decodeIfPresent(Float.self, forKey: .attenuationDistance)
        self.attenuationColor = try container.decodeIfPresent([Float].self, forKey: .attenuationColor) ?? [1, 1, 1]
    }
}

// MARK: - KHR_materials_ior extension
public struct KHRMaterialsIOR: Codable, Equatable {
    public let ior: Float
    enum CodingKeys: String, CodingKey {
        case ior
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.ior = try container.decodeIfPresent(Float.self, forKey: .ior) ?? 1.5
    }
}

// MARK: - KHR_materials_clearcoat extension
public struct KHRMaterialsClearcoat: Codable, Equatable {
    public let clearcoatFactor: Float
    public let clearcoatTexture: TextureInfo?
    public let clearcoatRoughnessFactor: Float
    public let clearcoatRoughnessTexture: TextureInfo?
    public let clearcoatNormalTexture: NormalTextureInfo?
    enum CodingKeys: String, CodingKey {
        case clearcoatFactor
        case clearcoatTexture
        case clearcoatRoughnessFactor
        case clearcoatRoughnessTexture
        case clearcoatNormalTexture
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.clearcoatFactor = try container.decodeIfPresent(Float.self, forKey: .clearcoatFactor) ?? 0.0
        self.clearcoatTexture = try container.decodeIfPresent(TextureInfo.self, forKey: .clearcoatTexture)
        self.clearcoatRoughnessFactor = try container.decodeIfPresent(Float.self, forKey: .clearcoatRoughnessFactor) ?? 0.0
        self.clearcoatRoughnessTexture = try container.decodeIfPresent(TextureInfo.self, forKey: .clearcoatRoughnessTexture)
        self.clearcoatNormalTexture = try container.decodeIfPresent(NormalTextureInfo.self, forKey: .clearcoatNormalTexture)
    }
}

// MARK: - KHR_materials_specular extension
public struct KHRMaterialsSpecular: Codable, Equatable {
    public let specularFactor: Float
    public let specularTexture: TextureInfo?
    public let specularColorFactor: [Float]
    public let specularColorTexture: TextureInfo?
    enum CodingKeys: String, CodingKey {
        case specularFactor
        case specularTexture
        case specularColorFactor
        case specularColorTexture
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.specularFactor = try container.decodeIfPresent(Float.self, forKey: .specularFactor) ?? 1.0
        self.specularTexture = try container.decodeIfPresent(TextureInfo.self, forKey: .specularTexture)
        self.specularColorFactor = try container.decodeIfPresent([Float].self, forKey: .specularColorFactor) ?? [1, 1, 1]
        self.specularColorTexture = try container.decodeIfPresent(TextureInfo.self, forKey: .specularColorTexture)
    }
}

// MARK: - KHR_materials_sheen extension
public struct KHRMaterialsSheen: Codable, Equatable {
    public let sheenColorFactor: [Float]
    public let sheenColorTexture: TextureInfo?
    public let sheenRoughnessFactor: Float
    public let sheenRoughnessTexture: TextureInfo?
    enum CodingKeys: String, CodingKey {
        case sheenColorFactor
        case sheenColorTexture
        case sheenRoughnessFactor
        case sheenRoughnessTexture
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.sheenColorFactor = try container.decodeIfPresent([Float].self, forKey: .sheenColorFactor) ?? [0, 0, 0]
        self.sheenColorTexture = try container.decodeIfPresent(TextureInfo.self, forKey: .sheenColorTexture)
        self.sheenRoughnessFactor = try container.decodeIfPresent(Float.self, forKey: .sheenRoughnessFactor) ?? 0.0
        self.sheenRoughnessTexture = try container.decodeIfPresent(TextureInfo.self, forKey: .sheenRoughnessTexture)
    }
}
