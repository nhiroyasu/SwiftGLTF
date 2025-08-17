import Foundation
import MetalKit
import SwiftGLTFCore
import OSLog

public func makeMDLAsset(from url: URL, options: GLTFDecodeOptions = .default) async throws -> MDLAsset {
    let data = try Data(contentsOf: url)
    let gltfContainer = try loadGLTF(from: data, baseURL: url.deletingLastPathComponent())
    return try await makeMDLAsset(from: gltfContainer, options: options)
}

public func makeMDLAsset(
    from gltfContainer: GLTFContainer,
    options: GLTFDecodeOptions = .default
) async throws -> MDLAsset {
    #if DEBUG
    let startTime = Date()
    defer {
        let elapsed = Date().timeIntervalSince(startTime)
        os_log("⏳ MDLAsset: Loaded in %{public}.2f seconds", log: .default, type: .info, elapsed)
    }
    #endif

    let gltf = gltfContainer.gltf

    let device = MTLCreateSystemDefaultDevice()!
    let allocator = MTKMeshBufferAllocator(device: device)
    let asset = MDLAsset(bufferAllocator: allocator)
    let binaryLoader = GLTFBinaryLoader(gltfContainer: gltfContainer)

    // 全ての mesh を先に変換して保持（再利用のため）
    // en: Convert all meshes first and keep them for reuse
    let mdlMeshMap = try await withThrowingTaskGroup(of: (MeshIndex, MDLObject).self) { group in
        for (index, mesh) in (gltf.meshes ?? []).enumerated() {
            group.addTask {
                let meshes = try makeMDLMesh(
                    from: mesh,
                    name: mesh.name ?? "Mesh_\(index)",
                    using: gltf,
                    allocator: allocator,
                    binaryLoader: binaryLoader,
                    options: options
                )
                return (MeshIndex(index), meshes)
            }
        }

        var result: [MeshIndex: MDLObject] = [:]
        for try await (index, meshes) in group {
            result[index] = meshes
        }
        return result
    }

    // 全ての skins を先に変換して保持
    // en: Convert all skins first and keep them for reuse
    var skinMap: [SkinIndex: GLTFSkeleton] = [:]
    for (index, skin) in (gltf.skins ?? []).enumerated() {
        let inverseBindTransforms = try {
            if let accessoryIndex = skin.inverseBindMatrices, let accessor = gltf.accessors?[accessoryIndex.value] {
                let data = try binaryLoader.extractData(accessorIndex: accessoryIndex)
                let matrixArray = MDLMatrix4x4Array(elementCount: accessor.count)
                matrixArray.float4x4Array = data.withUnsafeBytes { bytes in
                    Array(bytes.bindMemory(to: float4x4.self))
                }
                if options.convertToLeftHanded {
                     matrixArray.float4x4Array = matrixArray.float4x4Array.map { flipToLeftHanded($0) }
                }
                return matrixArray
            } else {
                let matrixArray = MDLMatrix4x4Array(elementCount: skin.joints.count)
                matrixArray.float4x4Array = [float4x4(1.0)]
                return matrixArray
            }
        }()
        let skeleton = GLTFSkeleton(
            name: skin.name ?? "Skin_\(index)",
            joins: skin.joints,
            inverseBindMatrices: inverseBindTransforms
        )
        skinMap[SkinIndex(index)] = skeleton
    }

    // デフォルトシーンを取得
    // en: Get the default scene
    let sceneIndex = gltf.scene ?? 0
    guard let scene = gltf.scenes?[sceneIndex] else {
        throw SwiftGLTFError.makeParse(.noValidScene, context: .capture(stage: .parse, jsonPointer: "/scene"))
    }

    // Build the node tree
    for rootNodeIndex in scene.nodes ?? [] {
        let root = buildNodeTree(nodeIndex: rootNodeIndex, meshMap: mdlMeshMap, skinMap: skinMap, gltf: gltf, options: options)
        asset.add(root)
    }

    if options.autoScale {
        let meshes = gltf.meshes ?? []
        let accessors = gltf.accessors ?? []
        let positionAccessorIndexOpt: Int? = meshes
            .flatMap { $0.primitives.map { $0.attributes[GLTFAttribute.position.rawValue] } }
            .first ?? nil
        if let positionAccessorIndex = positionAccessorIndexOpt,
           positionAccessorIndex < accessors.count,
           let max = accessors[positionAccessorIndex].max?.max() {
            let scale = 1 / max
            for i in 0..<asset.count {
                let matrix = asset.object(at: i).transform?.matrix ?? matrix_identity_float4x4
                asset.object(at: i).transform = GLTFTransform(matrix: scaleMatrix(scale, scale, scale) * matrix)
            }
            os_log("Scaling asset by factor: %{public}f", log: .default, type: .info, scale)
        }
    }

    return asset
}

public func makeMDLMesh(
    from mesh: Mesh,
    name: String,
    using gltf: GLTF,
    allocator: MTKMeshBufferAllocator,
    binaryLoader: GLTFBinaryLoader,
    options: GLTFDecodeOptions = .default
) throws -> MDLObject {
    let allocator = MTKMeshBufferAllocator(device: MTLCreateSystemDefaultDevice()!) // TODO: Metal device should be passed from outside

    let meshesObject = MDLObject()
    meshesObject.name = name
    for (index, primitive) in mesh.primitives.enumerated() {
        let accessors = gltf.accessors ?? []
        let materials = gltf.materials ?? []
        let vertexCount = retrieveVertexCount(for: primitive, accessors: accessors)

        // Make an index buffer
        let indexInfo = try makeIndexInfo(for: primitive, accessors: accessors, vertexCount: vertexCount, binaryLoader: binaryLoader)
        let indexBuffer = allocator.newBuffer(with: indexInfo.data, type: .index)

        // Make a vertex buffer
        let positionVertex = try makePositionVertex(for: primitive, accessors: accessors, binaryLoader: binaryLoader)
        var normalVertex = try makeNormalVertex(for: primitive, accessors: accessors, binaryLoader: binaryLoader)
        var tangentVertex = try makeTangentVertex(for: primitive, accessors: accessors, binaryLoader: binaryLoader)
        let texcoordVertex0 = try makeTexcoordVertex(for: primitive, accessors: accessors, binaryLoader: binaryLoader, texCoordIndex: 0)
        let texcoordVertex1 = try makeTexcoordVertex(for: primitive, accessors: accessors, binaryLoader: binaryLoader, texCoordIndex: 1)
        let modulationColorVertex = try makeModulationColorVertex(for: primitive, accessors: accessors, binaryLoader: binaryLoader)
        var jointsVertex = try makeJointVertex(for: primitive, accessors: accessors, binaryLoader: binaryLoader)
        var weightsVertex = try makeWeightVertex(for: primitive, accessors: accessors, binaryLoader: binaryLoader)

        // If JOINTS_0/WEIGHTS_0 are not both present, disable skinning
        if (jointsVertex == nil) != (weightsVertex == nil) {
            os_log("JOINTS_0/WEIGHTS_0 mismatch: disabling skinning for this primitive", log: .default, type: .info)
            jointsVertex = nil
            weightsVertex = nil
        }

        if normalVertex == nil,
           primitive.mode == .triangles {
            normalVertex = try generateNormalVertex(positionVertex: positionVertex, indexInfo: indexInfo)
        }

        if tangentVertex == nil,
           let normalVertex,
           let materialIndex = primitive.material,
           materials.indices.contains(materialIndex),
           let normalTexture = materials[materialIndex].normalTexture,
           primitive.mode == .triangles {
            let texCoord: VertexInfo? = switch normalTexture.texCoord {
            case 0: texcoordVertex0
            case 1: texcoordVertex1
            default: nil
            }
            if let texCoord {
                tangentVertex = try generateTangents(positionVertex, normalVertex, texCoord, indexInfo, vertexCount: vertexCount)
            }
        }

        let vertexDescriptor = try makeVertexDescriptor(
            positionVertex,
            normalVertex,
            tangentVertex,
            texcoordVertex0,
            texcoordVertex1,
            modulationColorVertex,
            jointsVertex,
            weightsVertex
        )

        let vertexData = makeVertexData(
            positionVertex,
            normalVertex,
            tangentVertex,
            texcoordVertex0,
            texcoordVertex1,
            modulationColorVertex,
            jointsVertex,
            weightsVertex,
            vertexCount: vertexCount,
            options: options
        )

        let vertexBuffer = allocator.newBuffer(with: vertexData, type: .vertex)

        // Create a MDLMaterial
        let mdlMaterial = try makeMDLMaterial(for: primitive, gltf, binaryLoader)

        // Calculate mesh center from POSITION accessor min/max and store to material property
        if let positionAccessorIndex = primitive.attributes[GLTFAttribute.position.rawValue] {
            let accessors = gltf.accessors ?? []
            if accessors.indices.contains(positionAccessorIndex) {
                let accessor = accessors[positionAccessorIndex]
                if let minVals = accessor.min, minVals.count >= 3,
                   let maxVals = accessor.max, maxVals.count >= 3 {
                    var center = SIMD3<Float>(
                        (minVals[0] + maxVals[0]) * 0.5,
                        (minVals[1] + maxVals[1]) * 0.5,
                        (minVals[2] + maxVals[2]) * 0.5
                    )
                    if options.convertToLeftHanded {
                        center.z = -center.z
                    }
                    let centerProp = MDLMaterialProperty(
                        name: MaterialPropertyName.meshCenter.rawValue,
                        semantic: .userDefined,
                        float3: center
                    )
                    mdlMaterial?.setProperty(centerProp)
                }
            }
        }

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
        mesh.name = "Primitive_\(index)"

        meshesObject.addChild(mesh)
    }

    return meshesObject
}

// 各ノードを再帰的に MDLObject に変換
// en: Recursively convert each node to MDLObject
func buildNodeTree(
    nodeIndex: Int,
    meshMap: [MeshIndex: MDLObject],
    skinMap: [SkinIndex: GLTFSkeleton],
    gltf: GLTF,
    options: GLTFDecodeOptions = .default
) -> MDLObject {
    let nodes = gltf.nodes ?? []
    let node: Node = {
        if nodes.indices.contains(nodeIndex) { return nodes[nodeIndex] }
        return Node(name: nil, mesh: nil, skin: nil, children: nil, translation: nil, rotation: nil, scale: nil, matrix: nil)
    }()
    let object = MDLObject()
    object.name = node.name ?? "Node_\(nodeIndex)" // ノード名が無ければデフォルト名を設定. en: Set default name if node name is missing

    // Add mesh if available
    if let meshIndex = node.mesh, let mesh = meshMap[meshIndex] {
        object.addChild(mesh)
    }

    // Add skin if available
    if let skinIndex = node.skin, let skin = skinMap[skinIndex] {
        object.addChild(skin)
    }

    for skin in skinMap.values {
        for (i, jointNodeIndex) in skin.joins.enumerated() {
            if nodeIndex == jointNodeIndex.value {
                skin.setJointObject(object, for: i)
            }
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
            let child = buildNodeTree(nodeIndex: childIndex, meshMap: meshMap, skinMap: skinMap, gltf: gltf, options: options)
            object.addChild(child)
        }
    }

    return object
}

func loadTextureSampler(
    for textureInfo: TextureInfo?,
    from gltf: GLTF,
    binaryLoader: GLTFBinaryLoader
) -> MDLTextureSampler? {
    guard let textureIndex = textureInfo?.index else { return nil }
    return loadTextureSampler(textureIndex: textureIndex, from: gltf, binaryLoader: binaryLoader)
}

func loadTextureSampler(
    for textureInfo: NormalTextureInfo?,
    from gltf: GLTF,
    binaryLoader: GLTFBinaryLoader
) -> MDLTextureSampler? {
    guard let textureIndex = textureInfo?.index else { return nil }
    return loadTextureSampler(textureIndex: textureIndex, from: gltf, binaryLoader: binaryLoader)
}

func loadTextureSampler(
    for textureInfo: OcclusionTextureInfo?,
    from gltf: GLTF,
    binaryLoader: GLTFBinaryLoader
) -> MDLTextureSampler? {
    guard let textureIndex = textureInfo?.index else { return nil }
    return loadTextureSampler(textureIndex: textureIndex, from: gltf, binaryLoader: binaryLoader)
}

// テクスチャ読み込みヘルパー
// en: Helper function to load texture sampler
func loadTextureSampler(
    textureIndex: TextureIndex,
    from gltf: GLTF,
    binaryLoader: GLTFBinaryLoader
) -> MDLTextureSampler? {
    // Load texture data via binaryLoader
    let textures = gltf.textures ?? []
    guard textureIndex.value < textures.count,
          let sourceIndex = textures[textureIndex.value].source else {
        return nil
    }
    let gltfTexture = textures[textureIndex.value]
    let mdlTexture: MDLTexture
    do {
        mdlTexture = try binaryLoader.extractTexture(textureIndex: sourceIndex)
    } catch {
        os_log("Texture not found for index %{public}d", log: .default, type: .error, sourceIndex.value)
        return nil
    }
    let sampler = MDLTextureSampler()
    sampler.texture = mdlTexture
    // Configure sampler filtering and wrapping if specified
    if let samplerIndex = gltfTexture.sampler {
        let samplers = gltf.samplers ?? []
        guard samplers.indices.contains(samplerIndex) else { return sampler }
        let gltfSampler = samplers[samplerIndex]
        let filter = MDLTextureFilter()
        if let magFilter = gltfSampler.magFilter {
            filter.magFilter = convertFilterMode(magFilter)
        } else {
            filter.magFilter = .linear
        }
        if let minFilter = gltfSampler.minFilter {
            filter.minFilter = convertFilterMode(minFilter)
        } else {
            filter.minFilter = .linear
        }
        filter.sWrapMode = convertWrapMode(gltfSampler.wrapS)
        filter.tWrapMode = convertWrapMode(gltfSampler.wrapT)
        sampler.hardwareFilter = filter
    }
    return sampler
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
    binaryLoader: GLTFBinaryLoader
) throws -> VertexInfo {
    guard let positionAccessorIndex = primitive.attributes[GLTFAttribute.position.rawValue] else {
        throw SwiftGLTFError.makeParse(
            .missingAttribute(name: "POSITION"),
            context: .capture(stage: .parse, jsonPointer: "/meshes/*/primitives/*/attributes/POSITION")
        )
    }
    guard accessors.count > positionAccessorIndex else {
        throw SwiftGLTFError.makeParse(
            .invalidAccessorIndex(name: "POSITION", index: positionAccessorIndex),
            context: .capture(stage: .parse)
        )
    }

    let positionAccessor = accessors[positionAccessorIndex]
    guard let positionVertexFormat = getMDLVertexFormat(accessor: positionAccessor) else {
        throw SwiftGLTFError.makeParse(.invalidAccessor(name: "POSITION"), context: .capture(stage: .parse))
    }
    let positionVertex = VertexInfo(
        data: try binaryLoader.extractData(accessorIndex: AccessorIndex(positionAccessorIndex)),
        componentFormat: positionVertexFormat.format,
        componentSize: positionVertexFormat.byteSize
    )
    return positionVertex
}

private func makeNormalVertex(
    for primitive: Primitive,
    accessors: [Accessor],
    binaryLoader: GLTFBinaryLoader
) throws -> VertexInfo? {
    guard let normalIndex = primitive.attributes[GLTFAttribute.normal.rawValue],
          accessors.indices.contains(normalIndex),
          let normalVertexFormat = getMDLVertexFormat(accessor: accessors[normalIndex]) else {
        return nil
    }
    return VertexInfo(
        data: try binaryLoader.extractData(accessorIndex: AccessorIndex(normalIndex)),
        componentFormat: normalVertexFormat.format,
        componentSize: normalVertexFormat.byteSize
    )
}

private func makeTangentVertex(
    for primitive: Primitive,
    accessors: [Accessor],
    binaryLoader: GLTFBinaryLoader
) throws -> VertexInfo? {
    guard let index = primitive.attributes[GLTFAttribute.tangent.rawValue],
          accessors.indices.contains(index),
          let format = getMDLVertexFormat(accessor: accessors[index]) else {
        return nil
    }
    return VertexInfo(
        data: try binaryLoader.extractData(accessorIndex: AccessorIndex(index)),
        componentFormat: format.format,
        componentSize: format.byteSize
    )
}

/// Read texcoord vertex for given TEXCOORD_i (i = texCoordIndex)
private func makeTexcoordVertex(
    for primitive: Primitive,
    accessors: [Accessor],
    binaryLoader: GLTFBinaryLoader,
    texCoordIndex: Int
) throws -> VertexInfo? {
    let key = GLTFAttribute.texcoord(texCoordIndex).rawValue
    guard let attrIndex = primitive.attributes[key],
          accessors.indices.contains(attrIndex),
          let format = getMDLVertexFormat(accessor: accessors[attrIndex]) else {
        return nil
    }
    return VertexInfo(
        data: try binaryLoader.extractData(accessorIndex: AccessorIndex(attrIndex)),
        componentFormat: format.format,
        componentSize: format.byteSize
    )
}

private func makeModulationColorVertex(
    for primitive: Primitive,
    accessors: [Accessor],
    binaryLoader: GLTFBinaryLoader
) throws -> VertexInfo? {
    guard let index = primitive.attributes[GLTFAttribute.color(0).rawValue],
          accessors.indices.contains(index),
          let format = getMDLVertexFormat(accessor: accessors[index]) else {
        return nil
    }
    return VertexInfo(
        data: try binaryLoader.extractData(accessorIndex: AccessorIndex(index)),
        componentFormat: format.format,
        componentSize: format.byteSize
    )
}

private func makeJointVertex(
    for primitive: Primitive,
    accessors: [Accessor],
    binaryLoader: GLTFBinaryLoader
) throws -> VertexInfo? {
    guard let attrIndex = primitive.attributes["JOINTS_0"], accessors.indices.contains(attrIndex) else {
        return nil
    }
    let accessor = accessors[attrIndex]
    guard accessor.type == .vec4 else {
        throw SwiftGLTFError.makeParse(.invalidVertexFormat(attribute: "JOINTS_0", expected: "VEC4"), context: .capture(stage: .parse))
    }
    switch accessor.componentType {
    case .unsignedByte, .unsignedShort:
        let raw = try binaryLoader.extractData(accessorIndex: AccessorIndex(attrIndex))
        if accessor.componentType == .unsignedShort {
            return VertexInfo(data: raw, componentFormat: .uShort4, componentSize: MemoryLayout<UInt16>.size * 4)
        } else {
            // Expand uChar4 -> uShort4
            var out = Data(capacity: accessor.count * MemoryLayout<UInt16>.size * 4)
            raw.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
                let src = ptr.bindMemory(to: UInt8.self)
                var i = 0
                while i < src.count {
                    let a = UInt16(src[i])
                    let b = UInt16(src[i+1])
                    let c = UInt16(src[i+2])
                    let d = UInt16(src[i+3])
                    var vals: [UInt16] = [a,b,c,d]
                    out.append(Data(bytes: &vals, count: MemoryLayout<UInt16>.size * 4))
                    i += 4
                }
            }
            return VertexInfo(data: out, componentFormat: .uShort4, componentSize: MemoryLayout<UInt16>.size * 4)
        }
    default:
        throw SwiftGLTFError.makeParse(.invalidVertexFormat(attribute: "JOINTS_0", expected: "uByte4 or uShort4"), context: .capture(stage: .parse))
    }
}

private func makeWeightVertex(
    for primitive: Primitive,
    accessors: [Accessor],
    binaryLoader: GLTFBinaryLoader
) throws -> VertexInfo? {
    guard let attrIndex = primitive.attributes["WEIGHTS_0"], accessors.indices.contains(attrIndex) else {
        return nil
    }
    let accessor = accessors[attrIndex]
    guard accessor.type == .vec4 else {
        throw SwiftGLTFError.makeParse(.invalidVertexFormat(attribute: "WEIGHTS_0", expected: "VEC4"), context: .capture(stage: .parse))
    }
    let count = accessor.count
    switch accessor.componentType {
    case .float:
        let raw = try binaryLoader.extractData(accessorIndex: AccessorIndex(attrIndex))
        // Ensure float4 stride
        return VertexInfo(data: raw, componentFormat: .float4, componentSize: MemoryLayout<Float>.size * 4)
    case .unsignedByte, .unsignedShort:
        let raw = try binaryLoader.extractData(accessorIndex: AccessorIndex(attrIndex))
        var out = Data(count: count * MemoryLayout<Float>.size * 4)
        out.withUnsafeMutableBytes { (dstPtr: UnsafeMutableRawBufferPointer) in
            let dst = dstPtr.bindMemory(to: Float.self)
            if accessor.componentType == .unsignedByte {
                raw.withUnsafeBytes { (srcPtr: UnsafeRawBufferPointer) in
                    let src = srcPtr.bindMemory(to: UInt8.self)
                    var i = 0
                    var o = 0
                    while i < src.count {
                        let a = Float(src[i]) / 255.0
                        let b = Float(src[i+1]) / 255.0
                        let c = Float(src[i+2]) / 255.0
                        let d = Float(src[i+3]) / 255.0
                        let sum = a + b + c + d
                        if sum > 0 {
                            let inv = 1.0 / sum
                            dst[o] = a * inv; dst[o+1] = b * inv; dst[o+2] = c * inv; dst[o+3] = d * inv
                        } else {
                            dst[o] = 0; dst[o+1] = 0; dst[o+2] = 0; dst[o+3] = 0
                        }
                        i += 4; o += 4
                    }
                }
            } else {
                raw.withUnsafeBytes { (srcPtr: UnsafeRawBufferPointer) in
                    let src = srcPtr.bindMemory(to: UInt16.self)
                    var i = 0
                    var o = 0
                    while i < src.count {
                        let a = Float(src[i]) / 65535.0
                        let b = Float(src[i+1]) / 65535.0
                        let c = Float(src[i+2]) / 65535.0
                        let d = Float(src[i+3]) / 65535.0
                        let sum = a + b + c + d
                        if sum > 0 {
                            let inv = 1.0 / sum
                            dst[o] = a * inv; dst[o+1] = b * inv; dst[o+2] = c * inv; dst[o+3] = d * inv
                        } else {
                            dst[o] = 0; dst[o+1] = 0; dst[o+2] = 0; dst[o+3] = 0
                        }
                        i += 4; o += 4
                    }
                }
            }
        }
        return VertexInfo(data: out, componentFormat: .float4, componentSize: MemoryLayout<Float>.size * 4)
    default:
        throw SwiftGLTFError.makeParse(.invalidVertexFormat(attribute: "WEIGHTS_0", expected: "float4|uByte4|uShort4"), context: .capture(stage: .parse))
    }
}

private func makeIndexInfo(
    for primitive: Primitive,
    accessors: [Accessor],
    vertexCount: Int,
    binaryLoader: GLTFBinaryLoader
) throws -> IndexInfo {
    if let indexAccessorIndex = primitive.indices {
        guard accessors.count > indexAccessorIndex.value else {
            throw SwiftGLTFError.makeParse(.invalidIndicesReference, context: .capture(stage: .parse))
        }

        let accessor = accessors[indexAccessorIndex.value]
        let indexData = try binaryLoader.extractData(accessorIndex: indexAccessorIndex)
        let indexCount = accessor.count

        let indexType: MDLIndexBitDepth
        switch accessor.componentType {
        case .unsignedByte: indexType = .uInt8
        case .unsignedShort: indexType = .uInt16
        case .unsignedInt: indexType = .uInt32
        default:
            throw SwiftGLTFError.makeParse(.unsupportedIndexType, context: .capture(stage: .parse))
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
    _ texcoordVertex0: VertexInfo?,
    _ texcoordVertex1: VertexInfo?,
    _ modulationColorVertex: VertexInfo?,
    _ jointsVertex: VertexInfo?,
    _ weightsVertex: VertexInfo?
) throws -> MDLVertexDescriptor {
    let descriptor = MDLVertexDescriptor()
    var offset = 0

    let positionIsFloat3 = positionVertex.componentFormat == .float3
    if !positionIsFloat3 {
        throw SwiftGLTFError.makeParse(.invalidVertexFormat(attribute: "POSITION", expected: "float3"), context: .capture(stage: .parse))
    }
    if let normalVertex {
        let normalIsFloat3 = normalVertex.componentFormat == .float3
        if !normalIsFloat3 {
            throw SwiftGLTFError.makeParse(.invalidVertexFormat(attribute: "NORMAL", expected: "float3"), context: .capture(stage: .parse))
        }
    }
    if let tangentVertex {
        if tangentVertex.componentFormat != .float4 {
            throw SwiftGLTFError.makeParse(.invalidVertexFormat(attribute: "TANGENT", expected: "float4"), context: .capture(stage: .parse))
        }
    }
    if let texcoordVertex0 {
        if texcoordVertex0.componentFormat != .float2 {
            throw SwiftGLTFError.makeParse(.invalidVertexFormat(attribute: "TEXCOORD", expected: "float2"), context: .capture(stage: .parse))
        }
    }
    if let texcoordVertex1 {
        if texcoordVertex1.componentFormat != .float2 {
            throw SwiftGLTFError.makeParse(.invalidVertexFormat(attribute: "TEXCOORD", expected: "float2"), context: .capture(stage: .parse))
        }
    }
    if let modulationColorVertex {
        if modulationColorVertex.componentFormat != .float3 && modulationColorVertex.componentFormat != .float4 {
            throw SwiftGLTFError.makeParse(.invalidVertexFormat(attribute: "COLOR", expected: "float3 or float4"), context: .capture(stage: .parse))
        }
    }
    if let jointsVertex {
        if jointsVertex.componentFormat != .uShort4 {
            throw SwiftGLTFError.makeParse(.invalidVertexFormat(attribute: "JOINTS_0", expected: "uShort4"), context: .capture(stage: .parse))
        }
    }
    if let weightsVertex {
        if weightsVertex.componentFormat != .float4 {
            throw SwiftGLTFError.makeParse(.invalidVertexFormat(attribute: "WEIGHTS_0", expected: "float4"), context: .capture(stage: .parse))
        }
    }

    descriptor.attributes[GLTFVertexAttributeIndex.POSITION] = MDLVertexAttribute(
        name: MDLVertexAttributePosition,
        format: .float3,
        offset: offset,
        bufferIndex: 0
    )
    offset += MemoryLayout<Float>.size * 3

    descriptor.attributes[GLTFVertexAttributeIndex.NORMAL] = MDLVertexAttribute(
        name: MDLVertexAttributeNormal,
        format: .float3,
        offset: offset,
        bufferIndex: 0
    )
    offset += MemoryLayout<Float>.size * 3

    descriptor.attributes[GLTFVertexAttributeIndex.TANGENT] = MDLVertexAttribute(
        name: MDLVertexAttributeTangent,
        format: .float4,
        offset: offset,
        bufferIndex: 0
    )
    offset += MemoryLayout<Float>.size * 4

    descriptor.attributes[GLTFVertexAttributeIndex.TEXCOORD_0] = MDLVertexAttribute(
        name: MDLVertexAttributeTextureCoordinate,
        format: .float2,
        offset: offset,
        bufferIndex: 0
    )
    offset += MemoryLayout<Float>.size * 2

    descriptor.attributes[GLTFVertexAttributeIndex.TEXCOORD_1] = MDLVertexAttribute(
        name: MDLVertexAttributeTextureCoordinate,
        format: .float2,
        offset: offset,
        bufferIndex: 0
    )
    offset += MemoryLayout<Float>.size * 2

    descriptor.attributes[GLTFVertexAttributeIndex.COLOR_0] = MDLVertexAttribute(
        name: MDLVertexAttributeColor,
        format: .float4,
        offset: offset,
        bufferIndex: 0
    )
    offset += MemoryLayout<Float>.size * 4

    descriptor.attributes[GLTFVertexAttributeIndex.JOINTS_0] = MDLVertexAttribute(
        name: MDLVertexAttributeJointIndices,
        format: .uShort4,
        offset: offset,
        bufferIndex: 0
    )
    offset += MemoryLayout<UInt16>.size * 4

    descriptor.attributes[GLTFVertexAttributeIndex.WEIGHTS_0] = MDLVertexAttribute(
        name: MDLVertexAttributeJointWeights,
        format: .float4,
        offset: offset,
        bufferIndex: 0
    )
    offset += MemoryLayout<Float>.size * 4

    descriptor.layouts[0] = MDLVertexBufferLayout(stride: offset)

    return descriptor
}

private func makeVertexData(
    _ positionVertex: VertexInfo,
    _ normalVertex: VertexInfo?,
    _ tangentVertex: VertexInfo?,
    _ texcoordVertex0: VertexInfo?,
    _ texcoordVertex1: VertexInfo?,
    _ modulationColorVertex: VertexInfo?,
    _ jointsVertex: VertexInfo?,
    _ weightsVertex: VertexInfo?,
    vertexCount: Int,
    options: GLTFDecodeOptions
) -> Data {
    var vertexData = Data()
    for i in 0..<vertexCount {
        // Position
        let posStride = positionVertex.componentSize
        let posBase = i * posStride
        let posSlice = positionVertex.data[posBase..<posBase+posStride]
        var posArray = posSlice.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        if options.convertToLeftHanded {
            posArray[2] = -posArray[2]
        }
        vertexData.append(Data(bytes: &posArray, count: posStride))

        // Normal
        if let normalVertex {
            let stride = normalVertex.componentSize
            let base = i * stride
            let slice = normalVertex.data[base..<base+stride]
            var normalArray = slice.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            if options.convertToLeftHanded {
                normalArray[2] = -normalArray[2]
            }
            vertexData.append(Data(bytes: &normalArray, count: stride))
        } else {
            // If no normal is provided, use default normal (0, 0, 1)
            var defaultNormal: [Float] = options.convertToLeftHanded ? [0, 0, -1] : [0, 0, 1]
            vertexData.append(Data(bytes: &defaultNormal, count: MemoryLayout<Float>.size * 3))
        }

        // Tangent
        if let tangentVertex {
            let stride = tangentVertex.componentSize
            let base = i * stride
            let slice = tangentVertex.data[base..<base+stride]
            var tangentArray = slice.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            if options.convertToLeftHanded {
                tangentArray[2] = -tangentArray[2]
            }
            vertexData.append(Data(bytes: &tangentArray, count: stride))
        } else {
            // If no tangent is provided, use default tangent (1, 0, 0, 1)
            // TODO: Is this okay?
            var defaultTangent: SIMD4<Float> = options.convertToLeftHanded ? SIMD4<Float>(1, 0, 0, -1) : SIMD4<Float>(1, 0, 0, 1)
            vertexData.append(Data(bytes: &defaultTangent, count: MemoryLayout<SIMD4<Float>>.size))
        }

        // Texcoord0
        if let tex0 = texcoordVertex0 {
            let stride = tex0.componentSize
            let base = i * stride
            let slice = tex0.data[base..<base+stride]
            vertexData.append(slice)
        } else {
            // Default texcoord0 (0,0)
            var defaultTexcoord0: SIMD2<Float> = SIMD2<Float>(0, 0)
            vertexData.append(Data(bytes: &defaultTexcoord0, count: MemoryLayout<SIMD2<Float>>.size))
        }

        // Texcoord1
        if let tex1 = texcoordVertex1 {
            let stride = tex1.componentSize
            let base = i * stride
            let slice = tex1.data[base..<base+stride]
            vertexData.append(slice)
        } else {
            // Default texcoord1 (0,0)
            var defaultTexcoord1: SIMD2<Float> = SIMD2<Float>(0, 0)
            vertexData.append(Data(bytes: &defaultTexcoord1, count: MemoryLayout<SIMD2<Float>>.size))
        }

        // Modulation Color
        if let modulationColorVertex {
            let stride = modulationColorVertex.componentSize
            let base = i * stride
            let slice = modulationColorVertex.data[base..<base+stride]
            if modulationColorVertex.componentFormat == .float3 {
                let arr = slice.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
                var color = SIMD4<Float>(arr[0], arr[1], arr[2], 1)
                vertexData.append(Data(bytes: &color, count: MemoryLayout<SIMD4<Float>>.size))
            } else {
                vertexData.append(slice)
            }
        } else {
            // If no modulation color is provided, use default color (1, 1, 1, 1)
            var defaultColor: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1)
            vertexData.append(Data(bytes: &defaultColor, count: MemoryLayout<SIMD4<Float>>.size))
        }

        // Joints
        if let jointsVertex {
            let stride = jointsVertex.componentSize
            let base = i * stride
            let slice = jointsVertex.data[base..<base+stride]
            vertexData.append(slice)
        } else {
            var defaultJoints: [UInt16] = [0, 0, 0, 0]
            vertexData.append(Data(bytes: &defaultJoints, count: MemoryLayout<UInt16>.size * 4))
        }

        // Weights
        if let weightsVertex {
            let stride = weightsVertex.componentSize
            let base = i * stride
            let slice = weightsVertex.data[base..<base+stride]
            vertexData.append(slice)
        } else {
            var defaultWeights: SIMD4<Float> = SIMD4<Float>(0, 0, 0, 0)
            vertexData.append(Data(bytes: &defaultWeights, count: MemoryLayout<SIMD4<Float>>.size))
        }
    }

    return vertexData
}

private func makeMDLMaterial(
    for primitive: Primitive,
    _ gltf: GLTF,
    _ binaryLoader: GLTFBinaryLoader
) throws -> MDLMaterial? {
    guard let materialIndex = primitive.material else {
        return nil
    }

    let materials = gltf.materials ?? []
    guard materials.count > materialIndex else {
        throw SwiftGLTFError.makeParse(.noValidMaterial, context: .capture(stage: .parse, jsonPointer: "/materials"))
    }

    let gltfMaterial = materials[materialIndex]

    let material = MDLMaterial(name: gltfMaterial.name ?? "Material \(materialIndex)",
                               scatteringFunction: MDLScatteringFunction())

    // Alpha mode / cutoff
    // glTF defaults: alphaMode = "OPAQUE", alphaCutoff = 0.5 (only for MASK)
    let alphaModeStr: String = gltfMaterial.alphaMode.rawValue
    let alphaModeProp = MDLMaterialProperty(
        name: MaterialPropertyName.alphaMode.rawValue,
        semantic: .userDefined,
        string: alphaModeStr
    )
    material.setProperty(alphaModeProp)

    let cutoffValue: Float = gltfMaterial.alphaCutoff
    let alphaCutoffProp = MDLMaterialProperty(
        name: MaterialPropertyName.alphaCutoff.rawValue,
        semantic: .userDefined,
        float: cutoffValue
    )
    material.setProperty(alphaCutoffProp)

    // Double-sided flag (store for renderer)
    let doubleSidedProp = MDLMaterialProperty(
        name: MaterialPropertyName.doubleSided.rawValue,
        semantic: .userDefined,
        float: gltfMaterial.doubleSided ? 1.0 : 0.0
    )
    material.setProperty(doubleSidedProp)

    // Normal Texture
    if let normalTexInfo = gltfMaterial.normalTexture,
       let sampler = loadTextureSampler(for: normalTexInfo, from: gltf, binaryLoader: binaryLoader) {
        let prop = MDLMaterialProperty(name: MaterialPropertyName.normalTexture.rawValue,
                                       semantic: .tangentSpaceNormal,
                                       textureSampler: sampler)
        material.setProperty(prop)
        // Store texCoord index for shader
        let coord = normalTexInfo.texCoord
        let coordProp = MDLMaterialProperty(name: MaterialPropertyName.normalTextureTexCoord.rawValue,
                                            semantic: .userDefined,
                                            float: Float(coord))
        material.setProperty(coordProp)
    }

    // PBR Metallic Roughness
    if let pbr = gltfMaterial.pbrMetallicRoughness {

        // Base Color
        let baseColorArr = pbr.baseColorFactor
        let baseColor: SIMD4<Float> = baseColorArr.count == 4
            ? SIMD4<Float>(baseColorArr[0], baseColorArr[1], baseColorArr[2], baseColorArr[3])
            : SIMD4<Float>(1.0, 1.0, 1.0, 1.0)
        let colorFactorProp = MDLMaterialProperty(
            name: MaterialPropertyName.baseColorFactor.rawValue,
            semantic: .baseColor,
            float4: SIMD4<Float>(baseColor[0], baseColor[1], baseColor[2], baseColor[3])
        )
        material.setProperty(colorFactorProp)

        if let sampler = loadTextureSampler(for: pbr.baseColorTexture, from: gltf, binaryLoader: binaryLoader) {
            let colorTextureProp = MDLMaterialProperty(
                name: MaterialPropertyName.baseColorTexture.rawValue,
                semantic: .baseColor,
                textureSampler: sampler
            )
            material.setProperty(colorTextureProp)
            // Store texCoord index for shader
            if let texInfo = pbr.baseColorTexture {
                let coord = texInfo.texCoord
                let coordProp = MDLMaterialProperty(name: MaterialPropertyName.baseColorTextureTexCoord.rawValue,
                                                    semantic: .userDefined,
                                                    float: Float(coord))
                material.setProperty(coordProp)
            }
        }

        // Metallic
        let metallicProp = MDLMaterialProperty(name: MaterialPropertyName.metallic.rawValue, semantic: .metallic, float: 1.0)
        metallicProp.floatValue = pbr.metallicFactor
        material.setProperty(metallicProp)

        // Roughness
        let roughnessProp = MDLMaterialProperty(name: MaterialPropertyName.roughness.rawValue, semantic: .roughness, float: 1.0)
        roughnessProp.floatValue = pbr.roughnessFactor
        material.setProperty(roughnessProp)

        // Metallic Roughness Texture
        if let metallicRoughnessTexture = pbr.metallicRoughnessTexture,
           let sampler = loadTextureSampler(for: metallicRoughnessTexture, from: gltf, binaryLoader: binaryLoader) {
            let metallicRoughnessProp = MDLMaterialProperty(name: MaterialPropertyName.metallicRoughnessTexture.rawValue, semantic: .userDefined, textureSampler: sampler)
            material.setProperty(metallicRoughnessProp)
            // Store texCoord index for shader
            let coord = metallicRoughnessTexture.texCoord
            let coordProp = MDLMaterialProperty(name: MaterialPropertyName.metallicRoughnessTextureTexCoord.rawValue,
                                                semantic: .userDefined,
                                                float: Float(coord))
            material.setProperty(coordProp)
        }

        // Emissive (with support for KHR_materials_emissive_strength)
        // Compute base emissive color
        var emissiveColor = simd_float3(0, 0, 0)
        let ef = gltfMaterial.emissiveFactor
        if ef.count == 3 {
            emissiveColor = simd_float3(ef[0], ef[1], ef[2])
        }
        // Apply emissive strength extension if present
        let emissiveStrength: Float = gltfMaterial.extensions?.khrMaterialsEmissiveStrength?.emissiveStrength ?? 1.0
        emissiveColor *= emissiveStrength

        let emissiveProp = MDLMaterialProperty(
            name: MaterialPropertyName.emissiveFactor.rawValue,
            semantic: .emission,
            float3: emissiveColor
        )
        material.setProperty(emissiveProp)

        if let emissiveTexture = gltfMaterial.emissiveTexture,
           let sampler = loadTextureSampler(for: emissiveTexture, from: gltf, binaryLoader: binaryLoader) {
            let emissiveTextureProp = MDLMaterialProperty(
                name: MaterialPropertyName.emissiveTexture.rawValue,
                semantic: .emission,
                textureSampler: sampler
            )
            material.setProperty(emissiveTextureProp)
            // Store texCoord index for shader
            let coord = emissiveTexture.texCoord
            let coordProp = MDLMaterialProperty(name: MaterialPropertyName.emissiveTextureTexCoord.rawValue,
                                                semantic: .userDefined,
                                                float: Float(coord))
            material.setProperty(coordProp)
        }

        // Occlusion
        let occlusionProp = MDLMaterialProperty(name: MaterialPropertyName.occlusion.rawValue, semantic: .ambientOcclusion)
        if let occlusionTexture = gltfMaterial.occlusionTexture,
           let sampler = loadTextureSampler(for: occlusionTexture, from: gltf, binaryLoader: binaryLoader) {
            occlusionProp.textureSamplerValue = sampler
        }
        material.setProperty(occlusionProp)
        // Store texCoord index for shader
        if let occlTex = gltfMaterial.occlusionTexture {
            let coord = occlTex.texCoord
            let coordProp = MDLMaterialProperty(name: MaterialPropertyName.occlusionTextureTexCoord.rawValue,
                                                semantic: .userDefined,
                                                float: Float(coord))
            material.setProperty(coordProp)
        }

        let occlusionStrengthProp = MDLMaterialProperty(name: MaterialPropertyName.occlusionStrength.rawValue, semantic: .ambientOcclusionScale, float: gltfMaterial.occlusionTexture?.strength ?? 1.0)
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
