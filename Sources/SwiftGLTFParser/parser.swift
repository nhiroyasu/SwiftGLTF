import Foundation
import MetalKit
import SwiftGLTFCore
import os.log

public func makeMDLAsset(from url: URL, options: GLTFDecodeOptions = .default) throws -> MDLAsset {
    let data = try Data(contentsOf: url)
    let gltfBundle = try loadGLTF(from: data, baseURL: url.deletingLastPathComponent())
    return try makeMDLAsset(from: gltfBundle, options: options)
}

public func makeMDLAsset(
    from gltfBundle: GLTFBundle,
    options: GLTFDecodeOptions = .default
) throws -> MDLAsset {
    #if DEBUG
    let startTime = Date()
    defer {
        let elapsed = Date().timeIntervalSince(startTime)
        os_log("⏳ MDLAsset: Loaded in %{public}.2f seconds", log: .default, type: .info, elapsed)
    }
    #endif

    let gltf = gltfBundle.gltf

    let device = MTLCreateSystemDefaultDevice()!
    let allocator = MTKMeshBufferAllocator(device: device)
    let asset = MDLAsset(bufferAllocator: allocator)
    let binaryLoader = GLTFBinaryLoader(gltfBundle: gltfBundle)

    let scenesObject = MDLObject()
    scenesObject.name = GLTFAssetName.scenes
    scenesObject.setComponent(GLTFDefaultSceneImpl(index: gltf.scene ?? 0), for: GLTFDefaultScene.self)
    asset.add(scenesObject)

    let camerasObject = MDLObject()
    camerasObject.name = GLTFAssetName.cameras
    asset.add(camerasObject)

    let librariesObject = MDLObject()
    librariesObject.name = GLTFAssetName.libraries
    asset.add(librariesObject)

    let skinsObject = MDLObject()
    skinsObject.name = GLTFAssetName.skins
    librariesObject.addChild(skinsObject)

    let mdlMaterials = try makeMDLMaterials(gltf, binaryLoader)
    let materialsObject = GLTFMaterials(
        materials: mdlMaterials
    )
    materialsObject.name = GLTFAssetName.materials
    librariesObject.addChild(materialsObject)

    let variantsInGLTF = gltf.extensions?.khrMaterialsVariants?.variants ?? []
    let variantsObject = GLTFVariants(
        variants: variantsInGLTF.enumerated().map { index, element in
            GLTFVariant(index: index, name: element.name ?? "Variant_\(index)")
        }
    )
    variantsObject.name = GLTFAssetName.variants
    librariesObject.addChild(variantsObject)

    // 全ての mesh を先に変換して保持（再利用のため）
    // en: Convert all meshes first and keep them for reuse
    var mdlMeshMap: [MeshIndex: [MDLMesh]] = [:]
    if let meshes = gltf.meshes, !meshes.isEmpty {
        for index in 0..<meshes.count {
            let mesh = meshes[index]
            let meshes = try makeMDLMesh(
                from: mesh,
                name: mesh.name ?? "Mesh_\(index)",
                using: gltf,
                allocator: allocator,
                binaryLoader: binaryLoader,
                mdlMaterials: mdlMaterials,
                options: options
            )
            mdlMeshMap[MeshIndex(index)] = meshes
        }
    }

    // Add all meshes to libraries for reference
    let meshesObject = MDLObject()
    meshesObject.name = GLTFAssetName.meshes
    let primitiveMeshes: [[MDLMesh]] = mdlMeshMap
        .sorted(by: { $0.key.value < $1.key.value })
        .map { $0.value }
    for (i, meshes) in primitiveMeshes.enumerated() {
        let primitiveMeshObject = GLTFPrimitiveMesh()
        meshesObject.addChild(primitiveMeshObject)
        primitiveMeshObject.name = GLTFAssetName.primitive(i)
        for mesh in meshes {
            primitiveMeshObject.addChild(mesh)
        }
    }
    librariesObject.addChild(meshesObject)

    // 全ての skins を先に変換して保持
    // en: Convert all skins first and keep them for reuse
    var skinMap: [SkinIndex: GLTFSkin] = [:]
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
        let skeleton = GLTFSkin(
            name: skin.name ?? "Skin_\(index)",
            joins: skin.joints,
            inverseBindMatrices: inverseBindTransforms
        )
        skinMap[SkinIndex(index)] = skeleton
    }

    // Skin nodes are added as children of the root asset
    for (_, skin) in skinMap.sorted(by: { $0.key.value < $1.key.value }) { // TODO: mapだと順番が保証されない
        skinsObject.addChild(skin)
    }

    // 全ての animations を先に変換して保持
    // en: Convert all animations first and keep them for reuse
    var animations: [MDLObject] = []
    for (index, anim) in (gltf.animations ?? []).enumerated() {
        var channels: [GLTFAnimationChannel] = []
        for channel in anim.channels {
            if let gltfAnimation = try GLTFAnimationChannelBuilder.build(
                from: channel,
                samplers: anim.samplers,
                gltf: gltf,
                binaryLoader: binaryLoader,
                options: options
            ) {
                channels.append(gltfAnimation)
            }
        }
        let duration: Float = channels.flatMap { $0.input }.max() ?? 0
        let animation = GLTFAnimationImpl(
            name: anim.name ?? "Animation_\(index)",
            duration: duration,
            channels: channels
        )
        let animObj = MDLObject()
        animObj.setComponent(animation, for: GLTFAnimation.self)
        animations.append(animObj)
    }
    let animationsContainer = GLTFAnimationContainer()
    for animObj in animations {
        animationsContainer.add(animObj)
    }
    asset.animations = animationsContainer

    let cameraMap = makeMDLCameras(from: gltf)
    for (_, mdlCamera) in cameraMap.sorted(by: { $0.key.value < $1.key.value }) {
        camerasObject.addChild(mdlCamera)
    }

    // Build the node tree
    for (i, scene) in (gltf.scenes ?? []).enumerated() {
        let sceneObject = MDLObject()
        sceneObject.name = GLTFAssetName.scene(i)
        scenesObject.addChild(sceneObject)

        let nodesObj = MDLObject()
        nodesObj.name = GLTFAssetName.nodes
        sceneObject.addChild(nodesObj)

        for rootNodeIndex in scene.nodes ?? [] {
            let node = buildNodeTree(
                nodeIndex: rootNodeIndex,
                meshMap: mdlMeshMap,
                skinMap: skinMap,
                cameraMap: cameraMap,
                animations: animations,
                gltf: gltf,
                options: options
            )
            nodesObj.addChild(node)
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
    mdlMaterials: [MDLMaterial],
    options: GLTFDecodeOptions = .default
) throws -> [MDLMesh] {
    let allocator = MTKMeshBufferAllocator(device: MTLCreateSystemDefaultDevice()!) // TODO: Metal device should be passed from outside

    var output: [MDLMesh] = []
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
            let texCoord: VertexInfo? = switch normalTexture.effectiveTexCoord {
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
        let mdlMaterial: MDLMaterial? = if let materialIndex = primitive.material {
            mdlMaterials[materialIndex]
        } else {
            nil
        }

        // Calculate mesh center from POSITION accessor min/max and store to material property
        // Used in distance sorting of transparent mesh
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

        let variantMappings: [GLTFVariantMapping] = primitive.extensions?.khrMaterialsVariants?.mappings.map {
            GLTFVariantMapping(
                variants: $0.variants.map(\.value),
                materialIndex: $0.material
            )
        } ?? []

        // Generate a submesh
        let submesh: MDLSubmesh
        submesh = GLTF_MDLSubmesh(
            name: "Submesh_\(index)",
            indexBuffer: indexBuffer,
            indexCount: indexInfo.count,
            indexType: indexInfo.type,
            geometryType: .triangles,
            material: mdlMaterial,
            materialIndex: primitive.material ?? -1,
            variantMappings: variantMappings
        )

        // Add the mesh to the list
        let mdlMesh = MDLMesh(
            vertexBuffer: vertexBuffer,
            vertexCount: vertexCount,
            descriptor: vertexDescriptor,
            submeshes: [submesh]
        )
        mdlMesh.name = "Primitive_\(index)"

        // Attach morph targets if present
        if let morph = try buildMorphTargets(
            for: primitive,
            meshName: name,
            primitiveIndex: index,
            accessors: accessors,
            vertexCount: vertexCount,
            allocator: allocator,
            binaryLoader: binaryLoader,
            options: options,
            meshDefaultWeights: mesh.weights
        ) {
            mdlMesh.setComponent(morph, for: GLTFMorphTargets.self)
        }

        output.append(mdlMesh)
    }

    return output
}

// 各ノードを再帰的に MDLObject に変換
// en: Recursively convert each node to MDLObject
func buildNodeTree(
    nodeIndex: Int,
    meshMap: [MeshIndex: [MDLMesh]],
    skinMap: [SkinIndex: GLTFSkin],
    cameraMap: [CameraIndex: MDLCamera],
    animations: [MDLObject],
    gltf: GLTF,
    options: GLTFDecodeOptions = .default
) -> MDLObject {
    let nodes = gltf.nodes ?? []
    let node: Node = {
        if nodes.indices.contains(nodeIndex) { return nodes[nodeIndex] }
        return Node(name: nil, mesh: nil, skin: nil, weights: nil, children: nil, translation: nil, rotation: nil, scale: nil, matrix: nil, camera: nil)
    }()

    let object: MDLObject
    if let cameraIndex = node.camera, let mdlCamera = cameraMap[cameraIndex] {
        object = GLTFCameraNode(
            nodeIndex: nodeIndex,
            cameraIndex: cameraIndex,
            camera: mdlCamera
        )
    } else {
        object = MDLObject()
    }
    object.name = node.name ?? "Node_\(nodeIndex)" // ノード名が無ければデフォルト名を設定. en: Set default name if node name is missing
    // Attach glTF node index for later animation application
    object.setComponent(GLTFNodeIndex(index: nodeIndex), for: GLTFNodeIndexProtocol.self)

    // Add mesh if available
    if let meshIndex = node.mesh {
        object.setComponent(GLTFMeshRefImpl(index: meshIndex.value), for: GLTFMeshRef.self)
    }

    // Add skin ref if available
    if let skinIndex = node.skin, let skin = skinMap[skinIndex] {
        object.setComponent(GLTFSkeletonRefImpl(skeleton: skin), for: GLTFSkeletonRef.self)
    }
    // Bind skeleton joints if this node is a joint
    for skin in skinMap.values {
        for (i, jointNodeIndex) in skin.joints.enumerated() {
            if nodeIndex == jointNodeIndex.value {
                skin.bind(object, for: i)
            }
        }
    }

    // Bind the animation channel to target node
    for animObj in animations {
        if let animComp = animObj.componentConforming(to: GLTFAnimation.self) as? GLTFAnimation {
            for channel in animComp.channels {
                if channel.targetNodeIndex.value == nodeIndex {
                    channel.bind(object)
                }
            }
        }
    }

    // Add morph  weights if available (per-node weights)
    if let weights = node.weights {
        let comp = GLTFMorphWeightsImpl(weights: weights)
        object.setComponent(comp, for: GLTFMorphWeights.self)
    }

    // トランスフォーム適用
    // en: Apply transformation
    if let matrix = node.matrix {
        let transformMatrix = float4x4(matrix)
        let finalMatrix = options.convertToLeftHanded ? flipToLeftHanded(transformMatrix) : transformMatrix
        object.transform = GLTFTransform(matrix: finalMatrix)
    } else {
        var translation: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
        if let t = node.translation {
            translation = SIMD3<Float>(t[0], t[1], t[2])
            if options.convertToLeftHanded {
                translation.z = -translation.z
            }
        }
        var rotation: simd_quatf = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        if let r = node.rotation {
            let q = simd_quatf(ix: r[0], iy: r[1], iz: r[2], r: r[3])
            if options.convertToLeftHanded {
                rotation = simd_quatf(ix: -q.imag.x, iy: -q.imag.y, iz: q.imag.z, r: q.real)
            }
        }
        var scale: SIMD3<Float> = SIMD3<Float>(1, 1, 1)
        if let s = node.scale {
            scale = SIMD3<Float>(s[0], s[1], s[2])
        }
        object.transform = GLTFTransform(translation: translation, rotation: rotation, scale: scale)
    }

    // 子ノードを再帰的に追加
    // en: Recursively add child nodes
    if let children = node.children {
        for childIndex in children {
            let child = buildNodeTree(
                nodeIndex: childIndex,
                meshMap: meshMap,
                skinMap: skinMap,
                cameraMap: cameraMap,
                animations: animations,
                gltf: gltf,
                options: options
            )
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
    } else {
        // Default sampler settings
        let filter = MDLTextureFilter()
        filter.magFilter = .linear
        filter.minFilter = .linear
        filter.sWrapMode = .repeat
        filter.tWrapMode = .repeat
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

@inline(__always)
private func setTextureTransform(
    _ transform: KHRTextureTransform?,
    material: MDLMaterial,
    offsetScaleName: MaterialPropertyName,
    rotationName: MaterialPropertyName
) {
    guard let transform else { return }
    let offset = transform.offset
    let scale = transform.scale
    let offsetScale = SIMD4<Float>(
        offset[0],
        offset[1],
        scale[0],
        scale[1]
    )
    let offsetScaleProp = MDLMaterialProperty(
        name: offsetScaleName.rawValue,
        semantic: .userDefined,
        float4: offsetScale
    )
    material.setProperty(offsetScaleProp)
    let rotationProp = MDLMaterialProperty(
        name: rotationName.rawValue,
        semantic: .userDefined,
        float: transform.rotation
    )
    material.setProperty(rotationProp)
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

private func makeMDLMaterials(
    _ gltf: GLTF,
    _ binaryLoader: GLTFBinaryLoader
) throws -> [MDLMaterial] {
    var materialsArray: [MDLMaterial] = []
    for (index, material) in (gltf.materials ?? []).enumerated() {
        let name = material.name ?? "Material \(index)"
        let mdlMaterial = try _makeMDLMaterial(name: name, gltfMaterial: material, gltf, binaryLoader)
        materialsArray.append(mdlMaterial)
    }
    return materialsArray
}

private func _makeMDLMaterial(
    name: String,
    gltfMaterial: Material,
    _ gltf: GLTF,
    _ binaryLoader: GLTFBinaryLoader
) throws -> MDLMaterial {
    let material = MDLMaterial(name: name, scatteringFunction: MDLScatteringFunction())

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

    if gltfMaterial.isUnlit {
        let unlitProp = MDLMaterialProperty(
            name: MaterialPropertyName.unlit.rawValue,
            semantic: .userDefined,
            float: 1.0
        )
        material.setProperty(unlitProp)
    }

    // Normal Texture
    if let normalTexInfo = gltfMaterial.normalTexture,
       let sampler = loadTextureSampler(for: normalTexInfo, from: gltf, binaryLoader: binaryLoader) {
        let prop = MDLMaterialProperty(name: MaterialPropertyName.normalTexture.rawValue,
                                       semantic: .tangentSpaceNormal,
                                       textureSampler: sampler)
        material.setProperty(prop)
        // Store texCoord index for shader
        let coord = normalTexInfo.effectiveTexCoord
        let coordProp = MDLMaterialProperty(name: MaterialPropertyName.normalTextureTexCoord.rawValue,
                                            semantic: .userDefined,
                                            float: Float(coord))
        material.setProperty(coordProp)
        setTextureTransform(
            normalTexInfo.textureTransform,
            material: material,
            offsetScaleName: .normalTextureTransformOffsetScale,
            rotationName: .normalTextureTransformRotation
        )
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
                let coord = texInfo.effectiveTexCoord
                let coordProp = MDLMaterialProperty(name: MaterialPropertyName.baseColorTextureTexCoord.rawValue,
                                                    semantic: .userDefined,
                                                    float: Float(coord))
                material.setProperty(coordProp)
                setTextureTransform(
                    texInfo.textureTransform,
                    material: material,
                    offsetScaleName: .baseColorTextureTransformOffsetScale,
                    rotationName: .baseColorTextureTransformRotation
                )
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
            let coord = metallicRoughnessTexture.effectiveTexCoord
            let coordProp = MDLMaterialProperty(name: MaterialPropertyName.metallicRoughnessTextureTexCoord.rawValue,
                                                semantic: .userDefined,
                                                float: Float(coord))
            material.setProperty(coordProp)
            setTextureTransform(
                metallicRoughnessTexture.textureTransform,
                material: material,
                offsetScaleName: .metallicRoughnessTextureTransformOffsetScale,
                rotationName: .metallicRoughnessTextureTransformRotation
            )
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
            let coord = emissiveTexture.effectiveTexCoord
            let coordProp = MDLMaterialProperty(name: MaterialPropertyName.emissiveTextureTexCoord.rawValue,
                                                semantic: .userDefined,
                                                float: Float(coord))
            material.setProperty(coordProp)
            setTextureTransform(
                emissiveTexture.textureTransform,
                material: material,
                offsetScaleName: .emissiveTextureTransformOffsetScale,
                rotationName: .emissiveTextureTransformRotation
            )
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
            let coord = occlTex.effectiveTexCoord
            let coordProp = MDLMaterialProperty(name: MaterialPropertyName.occlusionTextureTexCoord.rawValue,
                                                semantic: .userDefined,
                                                float: Float(coord))
            material.setProperty(coordProp)
            setTextureTransform(
                occlTex.textureTransform,
                material: material,
                offsetScaleName: .occlusionTextureTransformOffsetScale,
                rotationName: .occlusionTextureTransformRotation
            )
        }

        let occlusionStrengthProp = MDLMaterialProperty(name: MaterialPropertyName.occlusionStrength.rawValue, semantic: .ambientOcclusionScale, float: gltfMaterial.occlusionTexture?.strength ?? 1.0)
        material.setProperty(occlusionStrengthProp)
    }

    // KHR_materials_transmission
    if let transmission = gltfMaterial.extensions?.khrMaterialsTransmission {
        let tFactor = MDLMaterialProperty(
            name: MaterialPropertyName.transmissionFactor.rawValue,
            semantic: .userDefined,
            float: transmission.transmissionFactor
        )
        material.setProperty(tFactor)
        if let texInfo = transmission.transmissionTexture,
           let sampler = loadTextureSampler(for: texInfo, from: gltf, binaryLoader: binaryLoader) {
            let tTex = MDLMaterialProperty(
                name: MaterialPropertyName.transmissionTexture.rawValue,
                semantic: .userDefined,
                textureSampler: sampler
            )
            material.setProperty(tTex)
            let coordProp = MDLMaterialProperty(
                name: MaterialPropertyName.transmissionTextureTexCoord.rawValue,
                semantic: .userDefined,
                float: Float(texInfo.effectiveTexCoord)
            )
            material.setProperty(coordProp)
            setTextureTransform(
                texInfo.textureTransform,
                material: material,
                offsetScaleName: .transmissionTextureTransformOffsetScale,
                rotationName: .transmissionTextureTransformRotation
            )
        }
    }

    // KHR_materials_volume
    if let volume = gltfMaterial.extensions?.khrMaterialsVolume {
        let thickFactor = MDLMaterialProperty(
            name: MaterialPropertyName.thicknessFactor.rawValue,
            semantic: .userDefined,
            float: volume.thicknessFactor
        )
        material.setProperty(thickFactor)
        if let texInfo = volume.thicknessTexture,
           let sampler = loadTextureSampler(for: texInfo, from: gltf, binaryLoader: binaryLoader) {
            let tTex = MDLMaterialProperty(
                name: MaterialPropertyName.thicknessTexture.rawValue,
                semantic: .userDefined,
                textureSampler: sampler
            )
            material.setProperty(tTex)
            let coordProp = MDLMaterialProperty(
                name: MaterialPropertyName.thicknessTextureTexCoord.rawValue,
                semantic: .userDefined,
                float: Float(texInfo.effectiveTexCoord)
            )
            material.setProperty(coordProp)
            setTextureTransform(
                texInfo.textureTransform,
                material: material,
                offsetScaleName: .thicknessTextureTransformOffsetScale,
                rotationName: .thicknessTextureTransformRotation
            )
        }
        if let attnDist = volume.attenuationDistance {
            let attnDistProp = MDLMaterialProperty(
                name: MaterialPropertyName.attenuationDistance.rawValue,
                semantic: .userDefined,
                float: attnDist
            )
            material.setProperty(attnDistProp)
        }
        let c = volume.attenuationColor
        let color = SIMD3<Float>(c.count >= 3 ? c[0] : 1, c.count >= 3 ? c[1] : 1, c.count >= 3 ? c[2] : 1)
        let attnColorProp = MDLMaterialProperty(
            name: MaterialPropertyName.attenuationColor.rawValue,
            semantic: .userDefined,
            float3: color
        )
        material.setProperty(attnColorProp)
    }

    // KHR_materials_ior
    if let iorExt = gltfMaterial.extensions?.khrMaterialsIOR {
        let iorProp = MDLMaterialProperty(
            name: MaterialPropertyName.ior.rawValue,
            semantic: .userDefined,
            float: iorExt.ior
        )
        material.setProperty(iorProp)
    }

    // KHR_materials_clearcoat
    if let clearcoat = gltfMaterial.extensions?.khrMaterialsClearcoat {
        let ccFactor = MDLMaterialProperty(
            name: MaterialPropertyName.clearcoatFactor.rawValue,
            semantic: .userDefined,
            float: clearcoat.clearcoatFactor
        )
        material.setProperty(ccFactor)

        let ccRoughnessFactor = MDLMaterialProperty(
            name: MaterialPropertyName.clearcoatRoughnessFactor.rawValue,
            semantic: .userDefined,
            float: clearcoat.clearcoatRoughnessFactor
        )
        material.setProperty(ccRoughnessFactor)

        if let texInfo = clearcoat.clearcoatTexture,
           let sampler = loadTextureSampler(for: texInfo, from: gltf, binaryLoader: binaryLoader) {
            let ccTexture = MDLMaterialProperty(
                name: MaterialPropertyName.clearcoatTexture.rawValue,
                semantic: .userDefined,
                textureSampler: sampler
            )
            material.setProperty(ccTexture)
            let coordProp = MDLMaterialProperty(
                name: MaterialPropertyName.clearcoatTextureTexCoord.rawValue,
                semantic: .userDefined,
                float: Float(texInfo.effectiveTexCoord)
            )
            material.setProperty(coordProp)
            setTextureTransform(
                texInfo.textureTransform,
                material: material,
                offsetScaleName: .clearcoatTextureTransformOffsetScale,
                rotationName: .clearcoatTextureTransformRotation
            )
        }

        if let texInfo = clearcoat.clearcoatRoughnessTexture,
           let sampler = loadTextureSampler(for: texInfo, from: gltf, binaryLoader: binaryLoader) {
            let ccRoughnessTexture = MDLMaterialProperty(
                name: MaterialPropertyName.clearcoatRoughnessTexture.rawValue,
                semantic: .userDefined,
                textureSampler: sampler
            )
            material.setProperty(ccRoughnessTexture)
            let coordProp = MDLMaterialProperty(
                name: MaterialPropertyName.clearcoatRoughnessTextureTexCoord.rawValue,
                semantic: .userDefined,
                float: Float(texInfo.effectiveTexCoord)
            )
            material.setProperty(coordProp)
            setTextureTransform(
                texInfo.textureTransform,
                material: material,
                offsetScaleName: .clearcoatRoughnessTextureTransformOffsetScale,
                rotationName: .clearcoatRoughnessTextureTransformRotation
            )
        }

        if let normalInfo = clearcoat.clearcoatNormalTexture,
           let sampler = loadTextureSampler(for: normalInfo, from: gltf, binaryLoader: binaryLoader) {
            let ccNormalTexture = MDLMaterialProperty(
                name: MaterialPropertyName.clearcoatNormalTexture.rawValue,
                semantic: .userDefined,
                textureSampler: sampler
            )
            material.setProperty(ccNormalTexture)
            let coordProp = MDLMaterialProperty(
                name: MaterialPropertyName.clearcoatNormalTextureTexCoord.rawValue,
                semantic: .userDefined,
                float: Float(normalInfo.effectiveTexCoord)
            )
            material.setProperty(coordProp)
            let scaleProp = MDLMaterialProperty(
                name: MaterialPropertyName.clearcoatNormalTextureScale.rawValue,
                semantic: .userDefined,
                float: normalInfo.scale
            )
            material.setProperty(scaleProp)
            setTextureTransform(
                normalInfo.textureTransform,
                material: material,
                offsetScaleName: .clearcoatNormalTextureTransformOffsetScale,
                rotationName: .clearcoatNormalTextureTransformRotation
            )
        }
    }

    // KHR_materials_specular
    if let spec = gltfMaterial.extensions?.khrMaterialsSpecular {
        let sFactor = MDLMaterialProperty(
            name: MaterialPropertyName.specularFactor.rawValue,
            semantic: .userDefined,
            float: spec.specularFactor
        )
        material.setProperty(sFactor)
        let scfArr = spec.specularColorFactor
        let scf = SIMD3<Float>(scfArr.count >= 3 ? scfArr[0] : 1, scfArr.count >= 3 ? scfArr[1] : 1, scfArr.count >= 3 ? scfArr[2] : 1)
        let scProp = MDLMaterialProperty(
            name: MaterialPropertyName.specularColorFactor.rawValue,
            semantic: .userDefined,
            float3: scf
        )
        material.setProperty(scProp)
        if let texInfo = spec.specularTexture,
           let sampler = loadTextureSampler(for: texInfo, from: gltf, binaryLoader: binaryLoader) {
            let sTex = MDLMaterialProperty(
                name: MaterialPropertyName.specularTexture.rawValue,
                semantic: .userDefined,
                textureSampler: sampler
            )
            material.setProperty(sTex)
            let coordProp = MDLMaterialProperty(
                name: MaterialPropertyName.specularTextureTexCoord.rawValue,
                semantic: .userDefined,
                float: Float(texInfo.effectiveTexCoord)
            )
            material.setProperty(coordProp)
            setTextureTransform(
                texInfo.textureTransform,
                material: material,
                offsetScaleName: .specularTextureTransformOffsetScale,
                rotationName: .specularTextureTransformRotation
            )
        }
        if let texInfo = spec.specularColorTexture,
           let sampler = loadTextureSampler(for: texInfo, from: gltf, binaryLoader: binaryLoader) {
            let scTex = MDLMaterialProperty(
                name: MaterialPropertyName.specularColorTexture.rawValue,
                semantic: .userDefined,
                textureSampler: sampler
            )
            material.setProperty(scTex)
            let coordProp = MDLMaterialProperty(
                name: MaterialPropertyName.specularColorTextureTexCoord.rawValue,
                semantic: .userDefined,
                float: Float(texInfo.effectiveTexCoord)
            )
            material.setProperty(coordProp)
            setTextureTransform(
                texInfo.textureTransform,
                material: material,
                offsetScaleName: .specularColorTextureTransformOffsetScale,
                rotationName: .specularColorTextureTransformRotation
            )
        }
    }

    // KHR_materials_sheen
    if let sheen = gltfMaterial.extensions?.khrMaterialsSheen {
        let scfArr = sheen.sheenColorFactor
        let scf = SIMD3<Float>(scfArr.count >= 3 ? scfArr[0] : 0, scfArr.count >= 3 ? scfArr[1] : 0, scfArr.count >= 3 ? scfArr[2] : 0)
        let scfProp = MDLMaterialProperty(
            name: MaterialPropertyName.sheenColorFactor.rawValue,
            semantic: .userDefined,
            float3: scf
        )
        material.setProperty(scfProp)
        let srfProp = MDLMaterialProperty(
            name: MaterialPropertyName.sheenRoughnessFactor.rawValue,
            semantic: .userDefined,
            float: sheen.sheenRoughnessFactor
        )
        material.setProperty(srfProp)
        if let texInfo = sheen.sheenColorTexture,
           let sampler = loadTextureSampler(for: texInfo, from: gltf, binaryLoader: binaryLoader) {
            let scTex = MDLMaterialProperty(
                name: MaterialPropertyName.sheenColorTexture.rawValue,
                semantic: .userDefined,
                textureSampler: sampler
            )
            material.setProperty(scTex)
            let coordProp = MDLMaterialProperty(
                name: MaterialPropertyName.sheenColorTextureTexCoord.rawValue,
                semantic: .userDefined,
                float: Float(texInfo.effectiveTexCoord)
            )
            material.setProperty(coordProp)
            setTextureTransform(
                texInfo.textureTransform,
                material: material,
                offsetScaleName: .sheenColorTextureTransformOffsetScale,
                rotationName: .sheenColorTextureTransformRotation
            )
        }
        if let texInfo = sheen.sheenRoughnessTexture,
           let sampler = loadTextureSampler(for: texInfo, from: gltf, binaryLoader: binaryLoader) {
            let srTex = MDLMaterialProperty(
                name: MaterialPropertyName.sheenRoughnessTexture.rawValue,
                semantic: .userDefined,
                textureSampler: sampler
            )
            material.setProperty(srTex)
            let coordProp = MDLMaterialProperty(
                name: MaterialPropertyName.sheenRoughnessTextureTexCoord.rawValue,
                semantic: .userDefined,
                float: Float(texInfo.effectiveTexCoord)
            )
            material.setProperty(coordProp)
            setTextureTransform(
                texInfo.textureTransform,
                material: material,
                offsetScaleName: .sheenRoughnessTextureTransformOffsetScale,
                rotationName: .sheenRoughnessTextureTransformRotation
            )
        }
    }

    return material
}

func makeMDLCameras(from gltf: GLTF) -> [CameraIndex: MDLCamera] {
    var map: [CameraIndex: MDLCamera] = [:]
    guard let cameras = gltf.cameras else { return map }

    for (index, camera) in cameras.enumerated() {
        var mdlCamera = MDLCamera()
        mdlCamera.name = camera.name ?? "Camera_\(index)"

        switch camera.type {
        case .perspective:
            if let perspective = camera.perspective {
                mdlCamera = GLTFCamera(perspective: perspective)
            } else {
                // Invalid camera definition, skip
                continue
            }
        case .orthographic:
            if let orthographic = camera.orthographic {
                mdlCamera = GLTFCamera(orthographic: orthographic)
            } else {
                // Invalid camera definition, skip
                continue
            }
        }

        map[CameraIndex(index)] = mdlCamera
    }

    return map
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

// MARK: - Morph Target Helpers

private func extractMorphVec3Data(
    accessorIndex: Int,
    attributeName: String,
    accessors: [Accessor],
    vertexCount: Int,
    binaryLoader: GLTFBinaryLoader,
    options: GLTFDecodeOptions
) throws -> Data {
    guard accessors.indices.contains(accessorIndex) else {
        throw SwiftGLTFError.makeParse(
            .invalidAccessorIndex(name: "morph \(attributeName)", index: accessorIndex),
            context: .capture(stage: .parse)
        )
    }
    let accessor = accessors[accessorIndex]
    guard accessor.type == .vec3, accessor.componentType == .float else {
        throw SwiftGLTFError.makeParse(
            .invalidAccessor(name: "morph \(attributeName): must be VEC3 with FLOAT components"),
            context: .capture(stage: .parse)
        )
    }
    guard accessor.count == vertexCount else {
        throw SwiftGLTFError.makeParse(
            .invalidAccessor(name: "morph \(attributeName): vertex count mismatch"),
            context: .capture(stage: .parse)
        )
    }
    var data = try binaryLoader.extractData(accessorIndex: AccessorIndex(accessorIndex))
    if options.convertToLeftHanded {
        data.withUnsafeMutableBytes { (ptr: UnsafeMutableRawBufferPointer) in
            let f = ptr.bindMemory(to: Float.self)
            var i = 0
            while i + 2 < f.count {
                f[i+2] = -f[i+2]
                i += 3
            }
        }
    }
    return data
}

private func interleaveMorphData(
    position: Data?,
    normal: Data?,
    tangent: Data?,
    vertexCount: Int
) -> Data {
    let stride = MemoryLayout<Float>.size * 3 // vec3
    let totalStride = stride * 3              // pos + nrm + tan
    var interleaved = Data(capacity: vertexCount * totalStride)

    let pData = position
    let nData = normal
    let tData = tangent
    let zero = Data(count: stride)

    for i in 0..<vertexCount {
        // POSITION delta
        if let p = pData, p.count >= (i + 1) * stride {
            let base = i * stride
            interleaved.append(p[base..<(base + stride)])
        } else {
            interleaved.append(zero)
        }

        // NORMAL delta
        if let n = nData, n.count >= (i + 1) * stride {
            let base = i * stride
            interleaved.append(n[base..<(base + stride)])
        } else {
            interleaved.append(zero)
        }

        // TANGENT delta
        if let t = tData, t.count >= (i + 1) * stride {
            let base = i * stride
            interleaved.append(t[base..<(base + stride)])
        } else {
            interleaved.append(zero)
        }
    }

    return interleaved
}

private func makeMorphTargetMesh(
    interleavedData: Data,
    vertexCount: Int,
    allocator: MTKMeshBufferAllocator,
    name: String
) -> MDLMesh {
    let buffer = allocator.newBuffer(with: interleavedData, type: .vertex)
    let desc = MDLVertexDescriptor()
    var offset = 0
    desc.attributes[0] = MDLVertexAttribute(name: MDLVertexAttributePosition, format: .float3, offset: offset, bufferIndex: 0)
    offset += MemoryLayout<Float>.size * 3
    desc.attributes[1] = MDLVertexAttribute(name: MDLVertexAttributeNormal, format: .float3, offset: offset, bufferIndex: 0)
    offset += MemoryLayout<Float>.size * 3
    desc.attributes[2] = MDLVertexAttribute(name: MDLVertexAttributeTangent, format: .float3, offset: offset, bufferIndex: 0)
    offset += MemoryLayout<Float>.size * 3
    desc.layouts[0] = MDLVertexBufferLayout(stride: offset)
    let mesh = MDLMesh(vertexBuffer: buffer, vertexCount: vertexCount, descriptor: desc, submeshes: [])
    mesh.name = name
    return mesh
}

private func normalizedDefaultMorphWeights(
    targetCount: Int,
    meshWeights: [Float]?
) -> [Float] {
    let w = meshWeights ?? []
    if w.count == targetCount { return w }
    if w.count > targetCount { return Array(w.prefix(targetCount)) }
    return w + Array(repeating: 0.0, count: max(0, targetCount - w.count))
}

private func buildMorphTargets(
    for primitive: Primitive,
    meshName: String,
    primitiveIndex: Int,
    accessors: [Accessor],
    vertexCount: Int,
    allocator: MTKMeshBufferAllocator,
    binaryLoader: GLTFBinaryLoader,
    options: GLTFDecodeOptions,
    meshDefaultWeights: [Float]?
) throws -> GLTFMorphTargets? {
    guard let targets = primitive.targets, !targets.isEmpty else { return nil }

    var targetMeshes: [MDLMesh] = []
    targetMeshes.reserveCapacity(targets.count)
    for (tIdx, target) in targets.enumerated() {
        // If an attribute is provided in targets, validate its type strictly.
        var posData: Data? = nil
        if let idx = target[GLTFAttribute.position.rawValue] {
            posData = try extractMorphVec3Data(
                accessorIndex: idx,
                attributeName: GLTFAttribute.position.rawValue,
                accessors: accessors,
                vertexCount: vertexCount,
                binaryLoader: binaryLoader,
                options: options
            )
        }

        var nrmData: Data? = nil
        if let idx = target[GLTFAttribute.normal.rawValue] {
            nrmData = try extractMorphVec3Data(
                accessorIndex: idx,
                attributeName: GLTFAttribute.normal.rawValue,
                accessors: accessors,
                vertexCount: vertexCount,
                binaryLoader: binaryLoader,
                options: options
            )
        }

        var tanData: Data? = nil
        if let idx = target[GLTFAttribute.tangent.rawValue] {
            tanData = try extractMorphVec3Data(
                accessorIndex: idx,
                attributeName: GLTFAttribute.tangent.rawValue,
                accessors: accessors,
                vertexCount: vertexCount,
                binaryLoader: binaryLoader,
                options: options
            )
        }

        let interleaved = interleaveMorphData(position: posData, normal: nrmData, tangent: tanData, vertexCount: vertexCount)
        let name = "\(meshName)_Primitive_\(primitiveIndex)_Target_\(tIdx)"
        let targetMesh = makeMorphTargetMesh(interleavedData: interleaved, vertexCount: vertexCount, allocator: allocator, name: name)
        targetMeshes.append(targetMesh)
    }

    let defaultWeights = normalizedDefaultMorphWeights(targetCount: targets.count, meshWeights: meshDefaultWeights)
    return GLTFMorphTargetsImpl(
        vertexCount: vertexCount,
        targetCount: targets.count,
        targetMeshes: targetMeshes,
        defaultWeights: defaultWeights
    )
}
