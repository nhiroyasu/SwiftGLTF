import Foundation
import MetalKit
import SwiftGLTFCore
import OSLog

public enum GLTFVertexAttributeIndex {
    static let POSITION = 0
    static let NORMAL = 1
    static let TANGENT = 2
    static let TEXCOORD_0 = 3
    static let COLOR_0 = 4
}

public struct GLTFDecodeOptions: Sendable {
    /// Converts the model to left-handed coordinate system if true.
    public let convertToLeftHanded: Bool
    /// Automatically scales the model based on the maximum position value.
    public let autoScale: Bool
    /// If “NORMAL” is not defined in the glTF, normal data is created based on “POSITION”.
    public let generateNormalVertexIfNeeded: Bool
    /// If “TANGENT” is not defined in the glTF, the tangent data is created based on the MikkTSpace algorithm.
    ///
    /// "NORMAL" and "TEXCOORD_0" must be defined in the glTF.
    public let generateTangentVertexIfNeeded: Bool

    public static let `default` = GLTFDecodeOptions(
        convertToLeftHanded: true,
        autoScale: true,
        generateNormalVertexIfNeeded: true,
        generateTangentVertexIfNeeded: true
    )

    public init(
        convertToLeftHanded: Bool = true,
        autoScale: Bool = true,
        generateNormalVertexIfNeeded: Bool = true,
        generateTangentVertexIfNeeded: Bool = true
    ) {
        self.convertToLeftHanded = convertToLeftHanded
        self.autoScale = autoScale
        self.generateNormalVertexIfNeeded = generateNormalVertexIfNeeded
        self.generateTangentVertexIfNeeded = generateTangentVertexIfNeeded
    }
}

struct VertexInfo {
    let data: Data
    let componentFormat: MDLVertexFormat
    let componentSize: Int
}

struct IndexInfo {
    let data: Data
    let count: Int
    let type: MDLIndexBitDepth

    func getIndices() throws -> [Int] {
        try data.withUnsafeBytes {
           switch type {
           case .uInt8:
               let uint8Array = Array($0.bindMemory(to: UInt8.self))
               let intArray = Array<Int>(unsafeUninitializedCapacity: uint8Array.count) { buffer, initializedCount in
                   for (i, value) in uint8Array.enumerated() {
                       buffer[i] = Int(value)
                   }
                   initializedCount = uint8Array.count
               }
               return intArray
           case .uInt16:
               let uint16Array = Array($0.bindMemory(to: UInt16.self))
               let intArray = Array<Int>(unsafeUninitializedCapacity: uint16Array.count) { buffer, initializedCount in
                   for (i, value) in uint16Array.enumerated() {
                       buffer[i] = Int(value)
                   }
                   initializedCount = uint16Array.count
               }
               return intArray
           case .uInt32:
               let uint32Array = Array($0.bindMemory(to: UInt32.self))
               let intArray = Array<Int>(unsafeUninitializedCapacity: uint32Array.count) { buffer, initializedCount in
                   for (i, value) in uint32Array.enumerated() {
                       buffer[i] = Int(value)
                   }
                   initializedCount = uint32Array.count
               }
               return intArray
           default:
               throw NSError(domain: "GLTF", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unsupported index type for normal generation"])
           }
       }
    }
}



public func loadGLTF(from data: Data) throws -> GLTF {
    let decoder = JSONDecoder()
    let gltf = try decoder.decode(GLTF.self, from: data)
    return gltf
}

public func makeMDLMesh(
    from mesh: Mesh,
    using gltf: GLTF,
    bufferLoader: GLTFBufferLoader,
    preloadTextures: [Int: MDLTexture?],
    options: GLTFDecodeOptions = .default
) throws -> [MDLMesh] {
    let allocator = MTKMeshBufferAllocator(device: MTLCreateSystemDefaultDevice()!) // TODO: Metal device should be passed from outside

    var mdlMeshes: [MDLMesh] = []
    for (index, primitive) in mesh.primitives.enumerated() {
        let vertexCount = retrieveVertexCount(for: primitive, accessors: gltf.accessors ?? [])

        // Make an index buffer
        let indexInfo = try makeIndexInfo(for: primitive, accessors: gltf.accessors ?? [], vertexCount: vertexCount, bufferLoader: bufferLoader)
        let indexBuffer = allocator.newBuffer(with: indexInfo.data, type: .index)

        // Make a vertex buffer
        let positionVertex = try makePositionVertex(for: primitive, accessors: gltf.accessors ?? [], bufferLoader: bufferLoader)
        var normalVertex = try makeNormalVertex(for: primitive, accessors: gltf.accessors ?? [], bufferLoader: bufferLoader)
        var tangentVertex = try makeTangentVertex(for: primitive, accessors: gltf.accessors ?? [], bufferLoader: bufferLoader)
        let texcoordVertex = try makeTexcoordVertex(for: primitive, accessors: gltf.accessors ?? [], bufferLoader: bufferLoader)
        let modulationColorVertex = try makeModulationColorVertex(for: primitive, accessors: gltf.accessors ?? [], bufferLoader: bufferLoader)

        if options.generateNormalVertexIfNeeded,
           normalVertex == nil,
           primitive.mode == .triangles {
            os_log("Generating normals for primitives[%d]", log: .default, type: .info, index)
            normalVertex = try generateNormalVertex(positionVertex: positionVertex, indexInfo: indexInfo)
        }

        var isGeneratedTangents = false
        if options.generateTangentVertexIfNeeded, tangentVertex == nil,
           let normalVertex,
           let texcoordVertex,
           primitive.mode == .triangles {
            os_log("Generating tangents for primitive[%d]", log: .default, type: .info, index)
            tangentVertex = try generateTangents(positionVertex, normalVertex, texcoordVertex, indexInfo, vertexCount: vertexCount, options: options)
            isGeneratedTangents = true
        }

        let vertexDescriptor = makeVertexDescriptor(
            positionVertex,
            normalVertex,
            tangentVertex,
            texcoordVertex,
            modulationColorVertex
        )

        let vertexData = makeVertexData(
            positionVertex,
            normalVertex,
            tangentVertex,
            texcoordVertex,
            modulationColorVertex,
            vertexCount: vertexCount,
            options: options,
            isGeneratedTangents: isGeneratedTangents
        )

        let vertexBuffer = allocator.newBuffer(with: vertexData, type: .vertex)

        // Create a MDLMaterial
        let mdlMaterial = try makeMDLMaterial(for: primitive, gltf, bufferLoader, preloadTextures)

        // Generate a submesh
        let submesh: MDLSubmesh
        submesh = MDLSubmesh(
            indexBuffer: indexBuffer,
            indexCount: indexInfo.count,
            indexType: indexInfo.type,
            geometryType: .triangles,
            material: mdlMaterial
        )

        // Add the mesh to the list
        let mesh = MDLMesh(
            vertexBuffer: vertexBuffer,
            vertexCount: vertexCount,
            descriptor: vertexDescriptor,
            submeshes: [submesh]
        )
        mdlMeshes.append(mesh)
    }
    return mdlMeshes
}

public func makeMDLAsset(from gltf: GLTF, baseURL: URL, options: GLTFDecodeOptions = .default) throws -> MDLAsset {
    #if DEBUG
    let now = Date()
    #endif

    let device = MTLCreateSystemDefaultDevice()!
    let allocator = MTKMeshBufferAllocator(device: device)
    let asset = MDLAsset(bufferAllocator: allocator)
    let bufferLoader = try GLTFBufferLoader(gltf: gltf, baseURL: baseURL)
    let preloadTextures = preloadRawTextures(gltf, baseURL: baseURL)

    // 全ての mesh を先に変換して保持（再利用のため）
    // en: Convert all meshes first and keep them for reuse
    var mdlMeshMap: [Int: [MDLMesh]] = [:]
    for (index, mesh) in (gltf.meshes ?? []).enumerated() {
        mdlMeshMap[index] = try makeMDLMesh(
            from: mesh,
            using: gltf,
            bufferLoader: bufferLoader,
            preloadTextures: preloadTextures,
            options: options
        )
    }

    // デフォルトシーンを取得
    let sceneIndex = gltf.scene ?? 0
    guard let scene = gltf.scenes?[sceneIndex] else {
        throw NSError(domain: "GLTF", code: -1, userInfo: [NSLocalizedDescriptionKey: "No valid scene found"])
    }

    for rootNodeIndex in scene.nodes ?? [] {
        let root = buildNodeTree(gltf: gltf, mdlMeshMap: mdlMeshMap, nodeIndex: rootNodeIndex, options: options)
        asset.add(root)
    }

    if options.autoScale,
       let positionAccessorIndex = gltf.meshes?.flatMap({ $0.primitives.map({ $0.attributes[GLTFAttribute.position.rawValue]}) }).first?.flatMap({ $0 }),
       let positionAccessor = gltf.accessors?[positionAccessorIndex],
       let max = positionAccessor.max?.max() {
        let scale = 1 / max
        for i in 0..<asset.count {
            let matrix = asset.object(at: i).transform?.matrix ?? matrix_identity_float4x4
            asset.object(at: i).transform = GLTFTransform(matrix: scaleMatrix(scale, scale, scale) * matrix)
        }
        os_log("Scaling asset by factor: %{public}f", log: .default, type: .info, scale)
    }

    #if DEBUG
    let elapsed = Date().timeIntervalSince(now)
    os_log("MDLAsset created in %{public}.2f seconds", log: .default, type: .info, elapsed)
    #endif

    return asset
}

// 各ノードを再帰的に MDLObject に変換
// en: Recursively convert each node to MDLObject
func buildNodeTree(
    gltf: GLTF,
    mdlMeshMap: [Int: [MDLMesh]],
    nodeIndex: Int,
    options: GLTFDecodeOptions = .default
) -> MDLObject {
    let node = gltf.nodes![nodeIndex]
    let object = MDLObject()
    object.name = node.name ?? "Node \(nodeIndex)" // ノード名が無ければデフォルト名を設定. en: Set default name if node name is missing

    // メッシュがあれば追加
    // en: Add mesh if available
    if let meshIndex = node.mesh, let mdlMeshes = mdlMeshMap[meshIndex] {
        for mesh in mdlMeshes {
            object.addChild(mesh)
        }
    }

    // トランスフォーム適用
    // en: Apply transformation
    if let matrix = node.matrix {
        let transformMatrix = float4x4(matrix)
        let finalMatrix = options.convertToLeftHanded ? flipToLeftHanded(transformMatrix) : transformMatrix
        object.transform = GLTFTransform(matrix: finalMatrix)
    } else {
        var translation = float4x4(1.0)
        if let t = node.translation {
            translation = translationMatrix(t[0], t[1], t[2])
        }
        var rotation = float4x4(1.0)
        if let r = node.rotation {
            let q = simd_quatf(ix: r[0], iy: r[1], iz: r[2], r: r[3])
            rotation = quaternionMatrix(q)
        }
        var scale = float4x4(1.0)
        if let s = node.scale {
            scale = scaleMatrix(s[0], s[1], s[2])
        }
        let localMatrix = translation * rotation * scale
        let finalMatrix = options.convertToLeftHanded ? flipToLeftHanded(localMatrix) : localMatrix
        object.transform = GLTFTransform(matrix: finalMatrix)
    }

    // 子ノードを再帰的に追加
    // en: Recursively add child nodes
    if let children = node.children {
        for childIndex in children {
            let child = buildNodeTree(gltf: gltf, mdlMeshMap: mdlMeshMap, nodeIndex: childIndex, options: options)
            object.addChild(child)
        }
    }

    return object
}

func loadTextureSampler(
    for textureInfo: TextureInfo?,
    from gltf: GLTF, // TODO: All gltf objects are not needed. Just the textures are enough.
    textures: [Int: MDLTexture?]
) -> MDLTextureSampler? {
    guard let textureIndex = textureInfo?.index else {
        return nil
    }

    return loadTextureSampler(
        textureIndex: textureIndex,
        from: gltf,
        textures: textures
    )
}

func loadTextureSampler(
    for textureInfo: OcclusionTextureInfo?,
    from gltf: GLTF, // TODO: All gltf objects are not needed. Just the textures are enough.
    textures: [Int: MDLTexture?]
) -> MDLTextureSampler? {
    guard let textureIndex = textureInfo?.index else {
        return nil
    }

    return loadTextureSampler(
        textureIndex: textureIndex,
        from: gltf,
        textures: textures
    )
}

// テクスチャ読み込みヘルパー
// en: Helper function to load texture sampler
func loadTextureSampler(
    textureIndex: Int,
    from gltf: GLTF, // TODO: All gltf objects are not needed. Just the textures are enough.
    textures: [Int: MDLTexture?]
) -> MDLTextureSampler? {
    guard let texture = gltf.textures?[textureIndex],
          let sourceIndex = texture.source else {
        return nil
    }


    guard let mdlTexture = textures[sourceIndex] else {
        os_log("Texture not found for index %{public}d", log: .default, type: .error, sourceIndex)
        return nil
    }

    let sampler = MDLTextureSampler()
    sampler.texture = mdlTexture

    if let samplerIndex = texture.sampler {
        if let gltfSampler = gltf.samplers?[samplerIndex] {
            let filter = MDLTextureFilter()

            if let magFilter = gltfSampler.magFilter {
                filter.magFilter = convertFilterMode(magFilter)
            } else {
                // Set default value according to glTF specification
                filter.minFilter = .linear
            }
            if let minFilter = gltfSampler.minFilter {
                filter.minFilter = convertFilterMode(minFilter)
            } else {
                // Set default value according to glTF specification
                filter.minFilter = .linear
            }
            if let wrapS = gltfSampler.wrapS {
                filter.sWrapMode = convertWrapMode(wrapS)
            } else {
                // Set default value according to glTF specification
                filter.sWrapMode = .repeat
            }
            if let wrapT = gltfSampler.wrapT {
                filter.tWrapMode = convertWrapMode(wrapT)
            } else {
                // Set default value according to glTF specification
                filter.tWrapMode = .repeat
            }

            sampler.hardwareFilter = filter
        }
    }

    return sampler
}

func extractUrl(for info: TextureInfo?, from gltf: GLTF, baseURL: URL) -> URL? {
    guard let textureIndex = info?.index else {
        return nil
    }

    return extractUrl(textureIndex: textureIndex, from: gltf, baseURL: baseURL)
}

func extractUrl(for info: OcclusionTextureInfo?, from gltf: GLTF, baseURL: URL) -> URL? {
    guard let textureIndex = info?.index else {
        return nil
    }
    return extractUrl(textureIndex: textureIndex, from: gltf, baseURL: baseURL)
}

func extractUrl(textureIndex: Int, from gltf: GLTF, baseURL: URL) -> URL? {
    guard let texture = gltf.textures?[textureIndex],
          let sourceIndex = texture.source,
          let image = gltf.images?[sourceIndex],
          let uri = image.uri else {
        return nil
    }
    return baseURL.appendingPathComponent(uri)
}

private func convertFilterMode(_ mode: GLTFFilterMode) -> MDLMaterialTextureFilterMode {
    switch mode {
    case .nearest, .nearestMipmapNearest, .nearestMipmapLinear:
        return .nearest
    case .linear, .linearMipmapNearest, .linearMipmapLinear:
        return .linear
    }
}

private func convertWrapMode(_ mode: GLTFWrapMode) -> MDLMaterialTextureWrapMode {
    switch mode {
    case .clampToEdge:
        return .clamp
    case .mirroredRepeat:
        return .mirror
    case .repeatWrap:
        return .repeat
    }
}

private func preloadRawTextures(_ gltf: GLTF, baseURL: URL) -> [Int: MDLTexture?] {
    var textures: [Int: MDLTexture?] = [:]
    for (index, image) in (gltf.images ?? []).enumerated() {
        if let uri = image.uri, let url = URL(string: uri, relativeTo: baseURL) {
            let tex = MDLURLTexture(url: url, name: image.name ?? "Texture_\(index)")
            textures[index] = tex
        } else {
            textures[index] = nil
        }
    }
    return textures
}

private func retrieveVertexCount(
    for primitive: Primitive,
    accessors: [Accessor]
) -> Int {
    guard let positionAccessorIndex = primitive.attributes[GLTFAttribute.position.rawValue] else {
        return 0
    }
    guard accessors.count > positionAccessorIndex else {
        return 0
    }
    let positionAccessor = accessors[positionAccessorIndex]
    return positionAccessor.count
}

private func makePositionVertex(
    for primitive: Primitive,
    accessors: [Accessor],
    bufferLoader: GLTFBufferLoader
) throws -> VertexInfo {
    guard let positionAccessorIndex = primitive.attributes[GLTFAttribute.position.rawValue] else {
        throw NSError(domain: "GLTF", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing POSITION attribute"])
    }
    guard accessors.count > positionAccessorIndex else {
        throw NSError(domain: "GLTF", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid POSITION accessor index"])
    }

    let positionAccessor = accessors[positionAccessorIndex]
    guard let positionVertexFormat = getMDLVertexFormat(accessor: positionAccessor) else {
        throw NSError(domain: "GLTF", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid POSITION accessor"])
    }
    let positionVertex = VertexInfo(
        data: try bufferLoader.extractData(accessorIndex: positionAccessorIndex),
        componentFormat: positionVertexFormat.format,
        componentSize: positionVertexFormat.byteSize
    )
    return positionVertex
}

private func makeNormalVertex(
    for primitive: Primitive,
    accessors: [Accessor],
    bufferLoader: GLTFBufferLoader
) throws -> VertexInfo? {
    guard let normalIndex = primitive.attributes[GLTFAttribute.normal.rawValue],
          accessors.indices.contains(normalIndex),
          let normalVertexFormat = getMDLVertexFormat(accessor: accessors[normalIndex]) else {
        return nil
    }
    return VertexInfo(
        data: try bufferLoader.extractData(accessorIndex: normalIndex),
        componentFormat: normalVertexFormat.format,
        componentSize: normalVertexFormat.byteSize
    )
}

private func makeTangentVertex(
    for primitive: Primitive,
    accessors: [Accessor],
    bufferLoader: GLTFBufferLoader
) throws -> VertexInfo? {
    guard let index = primitive.attributes[GLTFAttribute.tangent.rawValue],
          accessors.indices.contains(index),
          let format = getMDLVertexFormat(accessor: accessors[index]) else {
        return nil
    }
    return VertexInfo(
        data: try bufferLoader.extractData(accessorIndex: index),
        componentFormat: format.format,
        componentSize: format.byteSize
    )
}

private func makeTexcoordVertex(
    for primitive: Primitive,
    accessors: [Accessor],
    bufferLoader: GLTFBufferLoader
) throws -> VertexInfo? {
    guard let index = primitive.attributes[GLTFAttribute.texcoord(0).rawValue],
          accessors.indices.contains(index),
          let format = getMDLVertexFormat(accessor: accessors[index]) else {
        return nil
    }
    return VertexInfo(
        data: try bufferLoader.extractData(accessorIndex: index),
        componentFormat: format.format,
        componentSize: format.byteSize
    )
}

private func makeModulationColorVertex(
    for primitive: Primitive,
    accessors: [Accessor],
    bufferLoader: GLTFBufferLoader
) throws -> VertexInfo? {
    guard let index = primitive.attributes[GLTFAttribute.color(0).rawValue],
          accessors.indices.contains(index),
          let format = getMDLVertexFormat(accessor: accessors[index]) else {
        return nil
    }
    return VertexInfo(
        data: try bufferLoader.extractData(accessorIndex: index),
        componentFormat: format.format,
        componentSize: format.byteSize
    )
}

private func makeIndexInfo(
    for primitive: Primitive,
    accessors: [Accessor],
    vertexCount: Int,
    bufferLoader: GLTFBufferLoader
) throws -> IndexInfo {
    if let indexAccessorIndex = primitive.indices {
        guard accessors.count > indexAccessorIndex else {
            throw NSError(domain: "GLTF", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid indices reference"])
        }

        let accessor = accessors[indexAccessorIndex]
        let indexData = try bufferLoader.extractData(accessorIndex: indexAccessorIndex)
        let indexCount = accessor.count

        let indexType: MDLIndexBitDepth
        switch accessor.componentType {
        case .unsignedByte: indexType = .uInt8
        case .unsignedShort: indexType = .uInt16
        case .unsignedInt: indexType = .uInt32
        default:
            throw NSError(domain: "GLTF", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unsupported index type"])
        }

        return IndexInfo(
            data: indexData,
            count: indexCount,
            type: indexType
        )
    } else {
        // glTF仕様に従い、インデックスが無ければ順番に0..N-1を生成
        // en: According to glTF specification, if no indices are provided, generate 0..N-1
        var indices = [UInt32](0..<UInt32(vertexCount))
        let indexData = Data(bytes: &indices, count: indices.count * MemoryLayout<UInt32>.size)
        let indexCount = vertexCount
        let indexType: MDLIndexBitDepth = .uInt32

        return IndexInfo(
            data: indexData,
            count: indexCount,
            type: indexType
        )
    }
}

private func makeVertexDescriptor(
    _ positionVertex: VertexInfo,
    _ normalVertex: VertexInfo?,
    _ tangentVertex: VertexInfo?,
    _ texcoordVertex: VertexInfo?,
    _ modulationColorVertex: VertexInfo?
) -> MDLVertexDescriptor {
    let descriptor = MDLVertexDescriptor()
    var offset = 0

    descriptor.attributes[GLTFVertexAttributeIndex.POSITION] = MDLVertexAttribute(
        name: MDLVertexAttributePosition,
        format: positionVertex.componentFormat,
        offset: offset,
        bufferIndex: 0
    )
    offset += positionVertex.componentSize

    if let normalVertex {
        descriptor.attributes[GLTFVertexAttributeIndex.NORMAL] = MDLVertexAttribute(
            name: MDLVertexAttributeNormal,
            format: normalVertex.componentFormat,
            offset: offset,
            bufferIndex: 0
        )
        offset += normalVertex.componentSize
    }

    if let tangentVertex {
        descriptor.attributes[GLTFVertexAttributeIndex.TANGENT] = MDLVertexAttribute(
            name: MDLVertexAttributeTangent,
            format: tangentVertex.componentFormat,
            offset: offset,
            bufferIndex: 0
        )
        offset += tangentVertex.componentSize
    }

    if let texcoordVertex {
        descriptor.attributes[GLTFVertexAttributeIndex.TEXCOORD_0] = MDLVertexAttribute(
            name: MDLVertexAttributeTextureCoordinate,
            format: texcoordVertex.componentFormat,
            offset: offset,
            bufferIndex: 0
        )
        offset += texcoordVertex.componentSize
    }

    if let modulationColorVertex {
        descriptor.attributes[GLTFVertexAttributeIndex.COLOR_0] = MDLVertexAttribute(
            name: MDLVertexAttributeColor,
            format: modulationColorVertex.componentFormat,
            offset: offset,
            bufferIndex: 0
        )
        offset += modulationColorVertex.componentSize
    }

    descriptor.layouts[0] = MDLVertexBufferLayout(stride: offset)

    return descriptor
}

private func makeVertexData(
    _ positionVertex: VertexInfo,
    _ normalVertex: VertexInfo?,
    _ tangentVertex: VertexInfo?,
    _ texcoordVertex: VertexInfo?,
    _ modulationColorVertex: VertexInfo?,
    vertexCount: Int,
    options: GLTFDecodeOptions,
    isGeneratedTangents: Bool
) -> Data {
    var vertexData = Data()
    for i in 0..<vertexCount {
        // Position
        if positionVertex.componentFormat == .float3 {
            let stride = positionVertex.componentSize
            let base = i * stride
            let slice = positionVertex.data[base..<base+stride]
            let floatArray = slice.withUnsafeBytes {
                Array($0.bindMemory(to: Float.self))
            }
            var vector = SIMD3<Float>(floatArray[0], floatArray[1], floatArray[2])
            if options.convertToLeftHanded {
                vector.z = -vector.z
            }
            vertexData.append(Data(bytes: &vector, count: stride))
        }

        // Normal
        if let normalVertex, normalVertex.componentFormat == .float3 {
            let stride = normalVertex.componentSize
            let base = i * stride
            let slice = normalVertex.data[base..<base+stride]
            let floatArray = slice.withUnsafeBytes {
                Array($0.bindMemory(to: Float.self))
            }
            var vector = SIMD3<Float>(floatArray[0], floatArray[1], floatArray[2])
            if options.convertToLeftHanded {
                vector.z = -vector.z
            }
            vertexData.append(Data(bytes: &vector, count: stride))
        }

        // Tangent
        if let tangentVertex, tangentVertex.componentFormat == .float4 {
            let stride = tangentVertex.componentSize
            let base = i * stride
            let slice = tangentVertex.data[base..<base+stride]
            let floatArray = slice.withUnsafeBytes {
                Array($0.bindMemory(to: Float.self))
            }
            var vector = SIMD4<Float>(floatArray[0], floatArray[1], floatArray[2], floatArray[3])
            if options.convertToLeftHanded, !isGeneratedTangents {
                vector.x = -vector.x
            }
            vertexData.append(Data(bytes: &vector, count: stride))
        }

        // Texcoord
        if let texcoordVertex {
            let stride = texcoordVertex.componentSize
            let base = i * stride
            let slice = texcoordVertex.data[base..<base+stride]
            vertexData.append(slice)
        }

        // Modulation Color
        if let modulationColorVertex {
            let stride = modulationColorVertex.componentSize
            let base = i * stride
            let slice = modulationColorVertex.data[base..<base+stride]
            vertexData.append(slice)
        }
    }

    return vertexData
}

private func makeMDLMaterial(
    for primitive: Primitive,
    _ gltf: GLTF,
    _ bufferLoader: GLTFBufferLoader,
    _ textures: [Int: MDLTexture?]
) throws -> MDLMaterial? {
    guard let materialIndex = primitive.material else {
        return nil
    }

    guard let materials = gltf.materials,
          materials.count > materialIndex else {
        throw NSError(domain: "GLTF", code: -1, userInfo: [NSLocalizedDescriptionKey: "No valid material found for materials \(String(describing: gltf.materials))"])
    }

    let gltfMaterial = materials[materialIndex]

    let material = MDLMaterial(name: gltfMaterial.name ?? "Material \(materialIndex)",
                               scatteringFunction: MDLScatteringFunction())

    // Normal Texture
    if let sampler = loadTextureSampler(for: gltfMaterial.normalTexture, from: gltf, textures: textures) {
        let prop = MDLMaterialProperty(name: "normalTexture", semantic: .tangentSpaceNormal, textureSampler: sampler)
        material.setProperty(prop)
    }

    // PBR Metallic Roughness
    if let pbr = gltfMaterial.pbrMetallicRoughness {

        // Base Color
        let colorProp = MDLMaterialProperty(name: "baseColor", semantic: .baseColor, float4: SIMD4<Float>(1, 1, 1, 1))
        if let baseColor = pbr.baseColorFactor, baseColor.count == 4 {
            colorProp.float4Value = SIMD4<Float>(baseColor[0], baseColor[1], baseColor[2], baseColor[3])
            colorProp.color = CGColor(red: CGFloat(baseColor[0]), green: CGFloat(baseColor[1]), blue: CGFloat(baseColor[2]), alpha: CGFloat(baseColor[3]))
        }
        if let sampler = loadTextureSampler(for: pbr.baseColorTexture, from: gltf, textures: textures) {
            colorProp.textureSamplerValue = sampler
            colorProp.urlValue = extractUrl(for: pbr.baseColorTexture, from: gltf, baseURL: bufferLoader.baseURL)
        }
        material.setProperty(colorProp)

        // Metallic
        let metallicProp = MDLMaterialProperty(name: "metallic", semantic: .metallic, float: 1.0)
        if let metallic = pbr.metallicFactor {
            metallicProp.floatValue = metallic
        }
        material.setProperty(metallicProp)

        // Roughness
        let roughnessProp = MDLMaterialProperty(name: "roughness", semantic: .roughness, float: 1.0)
        if let roughness = pbr.roughnessFactor {
            roughnessProp.floatValue = roughness
        }
        material.setProperty(roughnessProp)

        // Metallic Roughness Texture
        if let metallicRoughnessTexture = pbr.metallicRoughnessTexture,
           let sampler = loadTextureSampler(for: metallicRoughnessTexture, from: gltf, textures: textures) {
            let metallicRoughnessProp = MDLMaterialProperty(name: "metallicRoughnessTexture", semantic: .userDefined, textureSampler: sampler)
            material.setProperty(metallicRoughnessProp)
        }

        // Emissive (with support for KHR_materials_emissive_strength)
        // Compute base emissive color
        var emissiveColor = simd_float3(0, 0, 0)
        if let emissiveFactor = gltfMaterial.emissiveFactor, emissiveFactor.count >= 3 {
            emissiveColor = simd_float3(emissiveFactor[0], emissiveFactor[1], emissiveFactor[2])
        }
        // Apply emissive strength extension if present
        let emissiveStrength: Float = gltfMaterial.extensions?.khrMaterialsEmissiveStrength?.emissiveStrength ?? 1.0
        emissiveColor *= emissiveStrength
        let emissiveProp = MDLMaterialProperty(name: "emissive", semantic: .emission, float3: emissiveColor)
        if let emissiveTexture = gltfMaterial.emissiveTexture,
           let sampler = loadTextureSampler(for: emissiveTexture, from: gltf, textures: textures) {
            emissiveProp.textureSamplerValue = sampler
            emissiveProp.urlValue = extractUrl(for: emissiveTexture, from: gltf, baseURL: bufferLoader.baseURL)
        }
        material.setProperty(emissiveProp)

        // Occlusion
        let occlusionProp = MDLMaterialProperty(name: "occlusion", semantic: .ambientOcclusion)
        if let occlusionTexture = gltfMaterial.occlusionTexture,
           let sampler = loadTextureSampler(for: occlusionTexture, from: gltf, textures: textures) {
            occlusionProp.textureSamplerValue = sampler
            occlusionProp.urlValue = extractUrl(for: occlusionTexture, from: gltf, baseURL: bufferLoader.baseURL)
        }
        material.setProperty(occlusionProp)

        let occlusionStrengthProp = MDLMaterialProperty(name: "occlusionStrength", semantic: .ambientOcclusionScale, float: 1.0)
        if let occlusionStrength = gltfMaterial.occlusionTexture?.strength {
            occlusionStrengthProp.floatValue = occlusionStrength
        }
        material.setProperty(occlusionStrengthProp)
    }

    return material
}

private func generateNormalVertex(
    positionVertex: VertexInfo,
    indexInfo: IndexInfo
) throws -> VertexInfo {
    let indices: [Int] = try indexInfo.getIndices()

    let floatArrayPositions = positionVertex.data.withUnsafeBytes {
        Array($0.bindMemory(to: Float.self))
    }
    let positions: [SIMD3<Float>] = stride(from: 0, to: floatArrayPositions.count, by: 3).map { i in
        let x = floatArrayPositions[i]
        let y = floatArrayPositions[i + 1]
        let z = floatArrayPositions[i + 2]
        return SIMD3<Float>(x, y, z)
    }

    var normals: [SIMD3<Float>] = Array(repeating: SIMD3<Float>(0, 0, 0), count: positions.count)
    for i in stride(from: 0, to: indexInfo.count, by: 3) {
        let i0 = indices[i]
        let i1 = indices[i + 1]
        let i2 = indices[i + 2]

        let v0 = positions[i0]
        let v1 = positions[i1]
        let v2 = positions[i2]

        let edge1 = v1 - v0
        let edge2 = v2 - v0

        let faceNormal = simd_normalize(simd_cross(edge1, edge2))

        normals[i0] += faceNormal
        normals[i1] += faceNormal
        normals[i2] += faceNormal
    }

    var floatArrayNormals: [Float] = Array(repeating: 0.0, count: normals.count * 3)
    for i in 0..<normals.count {
        let normal = simd_normalize(normals[i])
        floatArrayNormals[i * 3] = normal.x
        floatArrayNormals[i * 3 + 1] = normal.y
        floatArrayNormals[i * 3 + 2] = normal.z
    }

    return VertexInfo(
        data: Data(bytes: &floatArrayNormals, count: floatArrayNormals.count * MemoryLayout<Float>.size),
        componentFormat: .float3,
        componentSize: MemoryLayout<Float>.size * 3
    )
}
