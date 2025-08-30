import MetalKit
import Accelerate
import SwiftGLTFParser
import SwiftGLTFCore
import SwiftGLTFShaderTypes

class PBRMeshLoader {
    private let device: MTLDevice
    private let pipelineConnector: PBRPipelineConnector
    private let shaderConnection: ShaderConnection
    private let textureLoader: MTKTextureLoader

    init(
        device: MTLDevice,
        shaderConnection: ShaderConnection,
        pipelineConnector: PBRPipelineConnector
    ) {
        self.device = device
        self.shaderConnection = shaderConnection
        self.pipelineConnector = pipelineConnector
        self.textureLoader = MTKTextureLoader(device: device)
    }

    func loadMeshes(
        from asset: MDLAsset,
        animationIndex: Int = 0
    ) async throws -> PBRMeshContainer {
        #if DEBUG
        let startTime = Date()
        defer {
            let elapsed = Date().timeIntervalSince(startTime)
            os_log("⏳ PBRMeshLoader: Loaded in %{public}.2f seconds", log: .default, type: .info, elapsed)
        }
        #endif

        let animations: [GLTFAnimation] = asset.animations.objects
            .compactMap({ $0.componentConforming(to: GLTFAnimationProtocol.self) as? GLTFAnimation })
        var animation: GLTFAnimation?
        if animationIndex < animations.count {
            animation = animations[animationIndex]
        }

        var textureMap = try extractAllTextureMap(from: asset)
        let texturesHeap = try makeTexturesHeap(from: Array(textureMap.values))
        if let texturesHeap {
            textureMap = try convertHeapTexture(from: textureMap, use: texturesHeap)
        }

        var skeletonMap: [GLTFSkeleton: PBRMesh.Skeleton] = try extractAllSkeletonMap(from: asset)
        let skeletonHeap = makeSkeletonHeap(
            skeletonBuffers: Array(skeletonMap.values.map({ $0.buffer }))
        )
        if let skeletonHeap {
            skeletonMap = try convertHeapSkeleton(from: skeletonMap, use: skeletonHeap)
        }

        let meshCount = extractAllMeshCounts(from: asset)
        let vertexBuffers = extractAllMeshVertexBuffer(from: asset)
        let morphVertexBuffers = extractAllMorphVertexBuffer(from: asset)
        let vertexHeap = try makeVertexHeap(from: meshCount, vertexBuffers: vertexBuffers + morphVertexBuffers)
        let fragmentHeap = try makeFragmentHeap(from: meshCount)

        var pbrMeshes: [PBRMesh] = []
        for i in 0..<asset.count {
            let rootObj = asset.object(at: i)
            let meshes = try await loadRecursiveMeshes(
                device: device,
                obj: rootObj,
                textureMap: textureMap,
                skeletonMap: skeletonMap,
                vertexHeap: vertexHeap,
                fragmentHeap: fragmentHeap,
                animation: animation,
                parentTransform: float4x4(1),
                parentTransformTree: [],
                parentAnimations: [],
                parentSkeletons: []
            )
            pbrMeshes.append(contentsOf: meshes)
        }

        return PBRMeshContainer(
            meshes: pbrMeshes,
            vertexResources: [vertexHeap, skeletonHeap].compactMap { $0 },
            fragmentResources: [texturesHeap, fragmentHeap].compactMap { $0 }
        )
    }

    private func loadRecursiveMeshes(
        device: MTLDevice,
        obj: MDLObject,
        textureMap: [MDLTexture: MTLTexture],
        skeletonMap: [GLTFSkeleton: PBRMesh.Skeleton],
        vertexHeap: MTLHeap,
        fragmentHeap: MTLHeap,
        animation: GLTFAnimation?,
        parentTransform: float4x4,
        parentTransformTree: [float4x4],
        parentAnimations: [PBRMesh.AnimationChannel],
        parentSkeletons: [GLTFSkeleton]
    ) async throws -> [PBRMesh] {
        var pbrMeshes: [PBRMesh] = []

        let selfTransform = obj.transform?.matrix ?? simd_float4x4(1)
        let totalTransform = parentTransform * selfTransform
        let transformTree = parentTransformTree + [selfTransform]

        var appliedAnimChannels = parentAnimations
        if let animation {
            for channel in animation.channels {
                if obj == channel.targetNode {
                    let meshAnim = PBRMesh.AnimationChannel(
                        type: channel.type,
                        interpolation: channel.interpolation,
                        input: channel.input,
                        modelMatrixTreeEffectIndex: transformTree.count - 1,
                        globalJointNodeTreeEffectIndex: nil,
                        globalJointMatrixTreeEffectIndex: nil
                    )
                    appliedAnimChannels.append(meshAnim)
                }
            }
        }

        var appliedSkeletons = parentSkeletons
        if let skeleton = (obj.componentConforming(to: GLTFSkeletonRef.self) as? GLTFSkeletonRef)?.skeleton {
            appliedSkeletons.append(skeleton)
        }

        if let mdlMesh = obj as? MDLMesh {
            let mtkMesh = try MTKMesh(mesh: mdlMesh, device: device)

            var hasSkinning = false
            var meshSkeleton: PBRMesh.Skeleton?
            if !appliedSkeletons.isEmpty {
                hasSkinning = true
                if appliedSkeletons.count > 1 {
                    os_log("⚠️ Warning: Multiple skeletons found for a mesh. Using the first one.", log: .default, type: .error)
                }
                let skeleton = appliedSkeletons.first!
                meshSkeleton = skeletonMap[skeleton]

                if let animation {
                    for channel in animation.channels {
                        for (nodeIndex, jointNode) in (skeleton.jointObjects).enumerated() {
                            for (jointMatrixIndex, node) in jointNode.parentTreeWithSelf.enumerated() {
                                if node == channel.targetNode {
                                    let meshAnim = PBRMesh.AnimationChannel(
                                        type: channel.type,
                                        interpolation: channel.interpolation,
                                        input: channel.input,
                                        modelMatrixTreeEffectIndex: nil,
                                        globalJointNodeTreeEffectIndex: nodeIndex,
                                        globalJointMatrixTreeEffectIndex: jointMatrixIndex
                                    )
                                    appliedAnimChannels.append(meshAnim)
                                }
                            }
                        }
                    }
                }
            }

            // Morph data detection on this mesh
            var hasMorph = false
            var morphCount: UInt32 = 0
            var morphWeightsBuffer: MTLBuffer? = nil
            var morphTargetBuffers: [MTLBuffer] = []
            if let morphComp = mdlMesh.componentConforming(to: GLTFMorphTargetsProtocol.self) as? GLTFMorphTargets {
                hasMorph = true
                morphCount = UInt32(morphComp.targetCount)

                // Determine weights: node weights if present, else default
                let nodeWeights = obj.parent?.parent?.componentConforming(to: GLTFMorphWeightsProtocol.self) as? GLTFMorphWeights
                let weights: [Float] = nodeWeights?.weights ?? morphComp.defaultWeights
                let tmpWeightsBuffer = device.makeBuffer(bytes: weights, length: MemoryLayout<Float>.size * weights.count)!
                morphWeightsBuffer = try shaderConnection.moveBufferToHeap(from: tmpWeightsBuffer, use: vertexHeap)

                // Convert target MDLMesh -> MTLBuffer (vertex buffer 0)
                for targetMDL in morphComp.targetMeshes.prefix(8) { // Limit to max 8
                    if let mtkTarget = try? MTKMesh(mesh: targetMDL, device: device) {
                        let heapBuf = try shaderConnection.moveBufferToHeap(from: mtkTarget.vertexBuffers[0].buffer, use: vertexHeap)
                        morphTargetBuffers.append(heapBuf)
                    }
                }
            }

            var submeshes: [PBRMesh.Submesh] = []
            for (mtkSubmesh, mdlSubmesh) in zip(mtkMesh.submeshes, mdlMesh.submeshes as! [MDLSubmesh]) {
                // Extract material factors to pass to shader
                let material = mdlSubmesh.material
                let baseColorFactor = material?.propertyNamed(.baseColorFactor)?.float4Value ?? SIMD4<Float>(1, 1, 1, 1)
                let metallicFactor = material?.propertyNamed(.metallic)?.floatValue ?? 1.0
                let roughnessFactor = material?.propertyNamed(.roughness)?.floatValue ?? 1.0
                let occlusionFactor = material?.propertyNamed(.occlusionStrength)?.floatValue ?? 1.0
                let emissiveFactor = material?.propertyNamed(.emissiveFactor)?.float3Value ?? SIMD3<Float>(0, 0, 0)

                // Base color texture and sampler
                var (hasBaseColorTexture, baseColorTexture, baseColorSamplerState) = retrieveTexture(prop: material?.propertyNamed(.baseColorTexture), textureMap: textureMap)

                // Normal texture and sampler
                var (hasNormalTexture, normalTexture, normalSamplerState) = retrieveTexture(prop: material?.propertyNamed(.normalTexture), textureMap: textureMap)

                // Make metallic roughness texture and sampler
                var (hasMetallicRoughnessTexture, metallicRoughnessTexture, metallicRoughnessSamplerState) = retrieveTexture(prop: material?.propertyNamed(.metallicRoughnessTexture), textureMap: textureMap)

                // Make emissive texture and sampler
                var (hasEmissiveTexture, emissiveTexture, emissiveSamplerState) = retrieveTexture(prop: material?.propertyNamed(.emissiveTexture), textureMap: textureMap)

                // Occlusion texture and sampler
                var (hasOcclusionTexture, occlusionTexture, occlusionSamplerState) = retrieveTexture(prop: material?.propertyNamed(.occlusion), textureMap: textureMap)

                // Retrieve texture coordinate indices and cast to UInt32
                let baseColorTexCoordF: Float = material?.propertyNamed(.baseColorTextureTexCoord)?.floatValue ?? 0.0
                let normalTexCoordF: Float = material?.propertyNamed(.normalTextureTexCoord)?.floatValue ?? 0.0
                let metalRoughnessTexCoordF: Float = material?.propertyNamed(.metallicRoughnessTextureTexCoord)?.floatValue ?? 0.0
                let emissiveTexCoordF: Float = material?.propertyNamed(.emissiveTextureTexCoord)?.floatValue ?? 0.0
                let occlusionTexCoordF: Float = material?.propertyNamed(.occlusionTextureTexCoord)?.floatValue ?? 0.0
                var baseColorTexCoord: UInt32 = UInt32(baseColorTexCoordF)
                var normalTexCoord: UInt32 = UInt32(normalTexCoordF)
                var metalRoughnessTexCoord: UInt32 = UInt32(metalRoughnessTexCoordF)
                var emissiveTexCoord: UInt32 = UInt32(emissiveTexCoordF)
                var occlusionTexCoord: UInt32 = UInt32(occlusionTexCoordF)
                // Alpha mode & cutoff
                let alphaModeStr = material?.propertyNamed(.alphaMode)?.stringValue?.uppercased() ?? "OPAQUE"
                let alphaModeEnum: AlphaMode = {
                    switch alphaModeStr {
                    case "MASK": return .mask
                    case "BLEND": return .blend
                    default: return .opaque
                    }
                }()
                var alphaModeRaw: UInt32 = alphaModeEnum.rawValue
                var alphaCutoff: Float = material?.propertyNamed(.alphaCutoff)?.floatValue ?? 0.5
                // Double sided flag
                let isDoubleSided: Bool = (material?.propertyNamed(.doubleSided)?.floatValue ?? 0) != 0
                // Create material uniforms buffer
                var materialUniforms = PBRMaterialUniforms(
                    baseColorFactor: baseColorFactor,
                    metalRoughnessOcclusion: SIMD4<Float>(metallicFactor, roughnessFactor, occlusionFactor, 0),
                    emissiveFactor: SIMD4<Float>(emissiveFactor.x, emissiveFactor.y, emissiveFactor.z, 0),
                    doubleSided: isDoubleSided ? 1 : 0
                )
                let tmpMaterialUniformsBuffer = device.makeBuffer(
                    bytes: &materialUniforms,
                    length: MemoryLayout<PBRMaterialUniforms>.size
                )!
                let materialUniformsBuffer = try shaderConnection.moveBufferToHeap(
                    from: tmpMaterialUniformsBuffer,
                    use: fragmentHeap
                )

                let argumentBuffer = try pipelineConnector.makeFragmentArgumentBuffer(
                    materialUniformsBuffer: materialUniformsBuffer,
                    hasBaseColorTexture: &hasBaseColorTexture,
                    baseColorTexture: baseColorTexture,
                    baseColorSampler: baseColorSamplerState,
                    hasNormalTexture: &hasNormalTexture,
                    normalTexture: normalTexture,
                    normalSampler: normalSamplerState,
                    hasMetallicRoughnessTexture: &hasMetallicRoughnessTexture,
                    metallicRoughnessTexture: metallicRoughnessTexture,
                    metallicRoughnessSampler: metallicRoughnessSamplerState,
                    hasEmissiveTexture: &hasEmissiveTexture,
                    emissiveTexture: emissiveTexture,
                    emissiveSampler: emissiveSamplerState,
                    hasOcclusionTexture: &hasOcclusionTexture,
                    occlusionTexture: occlusionTexture,
                    occlusionSampler: occlusionSamplerState,
                    // Pass texCoord indices
                    baseColorTexCoord: &baseColorTexCoord,
                    normalTexCoord: &normalTexCoord,
                    metallicRoughnessTexCoord: &metalRoughnessTexCoord,
                    emissiveTexCoord: &emissiveTexCoord,
                    occlusionTexCoord: &occlusionTexCoord,
                    // Alpha params
                    alphaMode: &alphaModeRaw,
                    alphaCutoff: &alphaCutoff
                )

                // Mesh center in model space (from parser via MDLMaterial property)
                let centerModelSpace: SIMD3<Float> = material?.propertyNamed(.meshCenter)?.float3Value ?? SIMD3<Float>(0, 0, 0)

                let submeshData = PBRMesh.Submesh(
                    primitiveType: mtkSubmesh.primitiveType,
                    indexCount: mtkSubmesh.indexCount,
                    indexType: mtkSubmesh.indexType,
                    indexBuffer: mtkSubmesh.indexBuffer,
                    fragmentArgumentBuffer: argumentBuffer,
                    alphaMode: alphaModeEnum,
                    alphaCutoff: alphaCutoff,
                    centerModelSpace: centerModelSpace,
                    doubleSided: isDoubleSided,
                    _storedHeapInstance: [
                        materialUniformsBuffer,
                        baseColorTexture,
                        baseColorSamplerState,
                        normalTexture,
                        normalSamplerState,
                        metallicRoughnessTexture,
                        metallicRoughnessSamplerState,
                        emissiveTexture,
                        emissiveSamplerState,
                        occlusionTexture,
                        occlusionSamplerState
                    ]
                )
                submeshes.append(submeshData)
            }

            let vertexBuffer = try shaderConnection.moveBufferToHeap(
                from: mtkMesh.vertexBuffers[0].buffer,
                use: vertexHeap
            )

            var model = totalTransform
            var inverseModel = model.inverse
            let tmpModelBuffer = device.makeBuffer(bytes: &model, length: MemoryLayout<float4x4>.size)!
            let tmpInverseModelBuffer = device.makeBuffer(bytes: &inverseModel, length: MemoryLayout<float4x4>.size)!
            let modelBuffer = try shaderConnection.moveBufferToHeap(from: tmpModelBuffer, use: vertexHeap)
            let inverseModelBuffer = try shaderConnection.moveBufferToHeap(from: tmpInverseModelBuffer, use: vertexHeap)

            let vertexArgumentBuffer = try pipelineConnector.makeVertexArgumentsBuffer(
                modelBuffer: modelBuffer,
                inverseModelBuffer: inverseModelBuffer,
                hasSkinning: &hasSkinning,
                globalJointMatricesBuffer: meshSkeleton?.buffer,
                hasMorph: hasMorph,
                morphTargetCount: morphCount,
                morphWeightsBuffer: morphWeightsBuffer,
                morphInterleavedBuffers: morphTargetBuffers
            )

            var meshAnimation: PBRMesh.Animation?
            if let animation, !appliedAnimChannels.isEmpty {
                meshAnimation = .init(
                    channels: appliedAnimChannels,
                    duration: animation.duration,
                    animatableBuffers: PBRMesh.AnimatableBuffers(
                        modelBuffer: modelBuffer,
                        inverseModelBuffer: inverseModelBuffer,
                        globalJointMatricesBuffer: meshSkeleton?.buffer,
                        morphWeightsBuffer: morphWeightsBuffer
                    )
                )
            }

            let pbrMesh = PBRMesh(
                vertexBuffer: vertexBuffer,
                vertexArgumentBuffer: vertexArgumentBuffer,
                submeshes: submeshes,
                animation: meshAnimation,
                modelMatrix: model,
                modelMatrixTree: transformTree,
                skeleton: meshSkeleton,
                _storedHeapInstance: [
                    morphWeightsBuffer,
                    modelBuffer,
                    inverseModelBuffer
                ] + morphTargetBuffers
            )
            pbrMeshes.append(pbrMesh)
        }

        for childObj in obj.children.objects {
            let childMeshes = try await loadRecursiveMeshes(
                device: device,
                obj: childObj,
                textureMap: textureMap,
                skeletonMap: skeletonMap,
                vertexHeap: vertexHeap,
                fragmentHeap: fragmentHeap,
                animation: animation,
                parentTransform: totalTransform,
                parentTransformTree: transformTree,
                parentAnimations: appliedAnimChannels,
                parentSkeletons: appliedSkeletons
            )
            pbrMeshes.append(contentsOf: childMeshes)
        }

        return pbrMeshes
    }

    func extractAllTextureMap(from asset: MDLAsset) throws -> [MDLTexture: MTLTexture] {
        var textureMap: [MDLTexture: MTLTexture] = [:]
        var needConvertionLinearSpace: [MDLTexture: MTLTexture] = [:]

        func traverse(object: MDLObject) throws {
            if let mesh = object as? MDLMesh {
                for submesh in mesh.submeshes ?? [] {
                    guard let mdlSubmesh = submesh as? MDLSubmesh, let material = mdlSubmesh.material else { continue }
                    for propertyIndex in 0..<material.count {
                        guard let property = material[propertyIndex], property.type == .texture,
                              let texture = property.textureSamplerValue?.texture else { continue }
                        let mtlTexture = try mdl2mtlTexture(texture)
                        textureMap[texture] = mtlTexture

                        if property.name == MaterialPropertyName.emissiveTexture.rawValue ||
                            property.name == MaterialPropertyName.baseColorTexture.rawValue {
                            needConvertionLinearSpace[texture] = mtlTexture
                        }
                    }
                }
            }

            for child in object.children.objects {
                try traverse(object: child)
            }
        }
        for objectIndex in 0..<asset.count {
            guard let object = asset[objectIndex] else { continue }
            try traverse(object: object)
        }

        // Convert textures that need linear space conversion
        let convertedTextures = try shaderConnection.convertSrgb2Linear(
            textures: Array(needConvertionLinearSpace.values)
        )
        for (index, dict) in needConvertionLinearSpace.enumerated() {
            textureMap[dict.key] = convertedTextures[index]
        }

        return textureMap
    }

    func extractAllSkeletonMap(from asset: MDLAsset) throws -> [GLTFSkeleton: PBRMesh.Skeleton] {
        var skeletonMap: [GLTFSkeleton: PBRMesh.Skeleton] = [:]

        for skeleton in asset.object(atPath: GLTFAssetPath.skins).children.objects.compactMap({ $0 as? GLTFSkeleton }) {
            var jointMatrices: [float4x4] = Array(repeating: float4x4(1), count: skeleton.jointObjects.count)
            var joints: [PBRMesh.Skeleton.Joint] = []
            joints.reserveCapacity(skeleton.jointObjects.count)
            for (index, jointObject) in skeleton.jointObjects.enumerated() {
                let inverseBindMatrix = skeleton.inverseBindMatrices.float4x4Array[index]
                let (globalJointTransform, globalJointTransformTree) = {
                    var skinNode = jointObject
                    var totalTransform = skinNode.transform?.matrix ?? float4x4(1)
                    var transformTree: [float4x4] = [totalTransform]
                    while let parent = skinNode.parent {
                        let parentTransform = parent.transform?.matrix ?? float4x4(1)
                        totalTransform = parentTransform * totalTransform
                        transformTree.insert(parentTransform, at: 0)
                        skinNode = parent
                    }
                    return (totalTransform, transformTree)
                }()

                let jointMatrix = globalJointTransform * inverseBindMatrix
                jointMatrices[index] = jointMatrix

                let joint = PBRMesh.Skeleton.Joint(
                    node: jointObject,
                    inverseBindMatrix: inverseBindMatrix,
                    globalJointMatrixTree: globalJointTransformTree,
                    globalJointTRSTree: globalJointTransformTree.map { decomposeTRS($0) }
                )
                joints.append(joint)
            }
            let buffer = device.makeBuffer(
                bytes: jointMatrices,
                length: MemoryLayout<float4x4>.size * jointMatrices.count,
                options: []
            )!
            skeletonMap[skeleton] = PBRMesh.Skeleton(
                buffer: buffer,
                jointMatrices: jointMatrices,
                joints: joints
            )
        }

        return skeletonMap
    }

    func extractAllMeshCounts(from asset: MDLAsset) -> Int {
        var meshCount = 0

        func traverse(object: MDLObject) {
            if let mesh = object as? MDLMesh {
                meshCount += mesh.submeshes?.count ?? 0
            }

            for child in object.children.objects {
                traverse(object: child)
            }
        }

        for objectIndex in 0..<asset.count {
            guard let object = asset[objectIndex] else { continue }
            traverse(object: object)
        }

        return meshCount
    }

    func extractAllMeshVertexBuffer(from asset: MDLAsset) -> [MDLMeshBuffer] {
        var buffers: [MDLMeshBuffer] = []

        func traverse(object: MDLObject) {
            if let mesh = object as? MDLMesh {
                buffers.append(contentsOf: mesh.vertexBuffers)
            }

            for child in object.children.objects {
                traverse(object: child)
            }
        }

        for objectIndex in 0..<asset.count {
            guard let object = asset[objectIndex] else { continue }
            traverse(object: object)
        }

        return buffers
    }

    func extractAllMorphVertexBuffer(from asset: MDLAsset) -> [MDLMeshBuffer] {
        var buffers: [MDLMeshBuffer] = []

        func traverse(object: MDLObject) {
            if let mesh = object as? MDLMesh {
                if let morph = mesh.componentConforming(to: GLTFMorphTargetsProtocol.self) as? GLTFMorphTargets {
                    for target in morph.targetMeshes {
                        if let buf = target.vertexBuffers.first { buffers.append(buf) }
                    }
                }
            }
            for child in object.children.objects { traverse(object: child) }
        }

        for objectIndex in 0..<asset.count {
            guard let object = asset[objectIndex] else { continue }
            traverse(object: object)
        }
        return buffers
    }

    func makeTexturesHeap(from textures: [MTLTexture]) throws -> MTLHeap? {
        let heapDescriptor = MTLHeapDescriptor()
        let size = textures
            .map { newDescriptorFromTexture($0, storageMode: .private) }
            .map { self.device.heapTextureSizeAndAlign(descriptor: $0)  }
            .map { $0.alignedSize }
            .reduce(0, +)
        guard size > 0 else { return nil }
        heapDescriptor.size = size
        heapDescriptor.storageMode = .private

        guard let texturesHeap = device.makeHeap(descriptor: heapDescriptor) else {
            throw SwiftGLTFError.makeRender(.texturesHeapCreateFailed, context: .capture(stage: .render))
        }
        return texturesHeap
    }

    func makeFragmentHeap(from meshCount: Int) throws -> MTLHeap {
        let heapDescriptor = MTLHeapDescriptor()

        let size = device.heapBufferSizeAndAlign(length: MemoryLayout<PBRMaterialUniforms>.size).alignedSize
        heapDescriptor.size = size * meshCount
        heapDescriptor.storageMode = .private

        guard heapDescriptor.size > 0 else {
            throw SwiftGLTFError.makeRender(.heapBufferCreateFailed, context: .capture(stage: .render))
        }
        guard let fragmentArgumentHeap = device.makeHeap(descriptor: heapDescriptor) else {
            throw SwiftGLTFError.makeRender(.fragmentArgumentHeapCreateFailed, context: .capture(stage: .render))
        }
        return fragmentArgumentHeap
    }

    func makeSkeletonHeap(skeletonBuffers: [MTLBuffer]) -> MTLHeap? {
        let heapDescriptor = MTLHeapDescriptor()

        let modelSize = device
            .heapBufferSizeAndAlign(length: skeletonBuffers.map({ $0.length }).reduce(0, +))
            .alignedSize

        heapDescriptor.size = modelSize
        heapDescriptor.storageMode = .private

        guard heapDescriptor.size > 0 else { return nil }
        guard let skeletonHeap = device.makeHeap(descriptor: heapDescriptor) else {
            return nil
        }
        return skeletonHeap
    }

    func makeVertexHeap(from meshCount: Int, vertexBuffers: [MDLMeshBuffer]) throws -> MTLHeap {
        let heapDescriptor = MTLHeapDescriptor()

        let modelSize = device.heapBufferSizeAndAlign(length: MemoryLayout<float4x4>.size).alignedSize * meshCount
        let inverseModelSize = device.heapBufferSizeAndAlign(length: MemoryLayout<float4x4>.size).alignedSize * meshCount

        var bufferSize: Int = 0
        for vertexBuffer in vertexBuffers {
            let size = device.heapBufferSizeAndAlign(length: vertexBuffer.length).alignedSize
            bufferSize += size
        }

        heapDescriptor.size = modelSize + inverseModelSize + bufferSize
        heapDescriptor.storageMode = .private

        guard heapDescriptor.size > 0 else {
            throw SwiftGLTFError.makeRender(.heapBufferCreateFailed, context: .capture(stage: .render))
        }
        guard let vertexModelHeap = device.makeHeap(descriptor: heapDescriptor) else {
            throw SwiftGLTFError.makeRender(.vertexModelHeapCreateFailed, context: .capture(stage: .render))
        }
        return vertexModelHeap
    }

    func convertHeapTexture(from textureMap: [MDLTexture: MTLTexture], use heap: MTLHeap) throws -> [MDLTexture: MTLTexture] {
        var convertedMap: [MDLTexture: MTLTexture] = [:]
        for (mdlTexture, mtlTexture) in textureMap {
            let heapTexture = try shaderConnection.moveResourceToHeap(from: mtlTexture, use: heap)
            convertedMap[mdlTexture] = heapTexture
        }
        return convertedMap
    }

    func convertHeapSkeleton(from skeletonMap: [GLTFSkeleton: PBRMesh.Skeleton], use heap: MTLHeap) throws -> [GLTFSkeleton: PBRMesh.Skeleton] {
        var convertedMap: [GLTFSkeleton: PBRMesh.Skeleton] = [:]
        let heapBuffers = try shaderConnection.moveBuffersToHeap(
            from: Array(skeletonMap.values.map({ $0.buffer })),
            use: heap
        )
        for (index, element) in skeletonMap.enumerated() {
            let skeleton = element.key
            let data = element.value
            convertedMap[skeleton] = .init(
                buffer: heapBuffers[index],
                jointMatrices: data.jointMatrices,
                joints: data.joints
            )
        }
        return convertedMap
    }

    // MARK: - Texture & Sampler Helpers

    private func retrieveTexture(prop: MDLMaterialProperty?, textureMap: [MDLTexture: MTLTexture]) -> (Bool, MTLTexture?, MTLSamplerState?) {
        guard let tex = prop?.textureSamplerValue?.texture else { return (false, nil, nil) }
        let mtlTexture = textureMap[tex]

        guard let sampler = prop?.textureSamplerValue else { return (false, nil, nil) }
        let samplerState = try? makeSamplerState(from: sampler, device: device)

        if let mtlTexture, let samplerState {
            return (true, mtlTexture, samplerState)
        } else {
            return (false, nil, nil)
        }
    }

    private func mdl2mtlTexture(_ mdlTexture: MDLTexture) throws -> MTLTexture {
        return try textureLoader.newTexture(
            texture: mdlTexture,
            options: [
                .origin: MTKTextureLoader.Origin.topLeft,
                .textureStorageMode: NSNumber(value: MTLStorageMode.private.rawValue),
                .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue)
            ]
        )
    }

    private func makeSamplerState(from sampler: MDLTextureSampler, device: MTLDevice) throws -> MTLSamplerState {
        let descriptor = MTLSamplerDescriptor()
        descriptor.supportArgumentBuffers = true

        switch sampler.hardwareFilter?.magFilter {
        case .nearest: descriptor.magFilter = .nearest
        case .linear: descriptor.magFilter = .linear
        default: break
        }

        switch sampler.hardwareFilter?.minFilter {
        case .nearest: descriptor.minFilter = .nearest
        case .linear: descriptor.minFilter = .linear
        default: break
        }

        switch sampler.hardwareFilter?.sWrapMode {
        case .clamp: descriptor.sAddressMode = .clampToEdge
        case .repeat: descriptor.sAddressMode = .repeat
        case .mirror: descriptor.sAddressMode = .mirrorRepeat
        default: break
        }

        switch sampler.hardwareFilter?.tWrapMode {
        case .clamp: descriptor.tAddressMode = .clampToEdge
        case .repeat: descriptor.tAddressMode = .repeat
        case .mirror: descriptor.tAddressMode = .mirrorRepeat
        default: break
        }

        if let samplerState = device.makeSamplerState(descriptor: descriptor) {
            return samplerState
        } else {
            throw SwiftGLTFError.makeRender(.argumentBufferCreateFailed, context: .capture(stage: .render))
        }
    }
}
