import MetalKit
import Accelerate
import SwiftGLTFParser
import SwiftGLTFCore

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

    func loadMeshes(from asset: MDLAsset) async throws -> PBRMeshContainer {
        #if DEBUG
        let startTime = Date()
        defer {
            let elapsed = Date().timeIntervalSince(startTime)
            os_log("⏳ PBRMeshLoader: Loaded in %{public}.2f seconds", log: .default, type: .info, elapsed)
        }
        #endif

        var textureMap = try extractAllTextureMap(from: asset)
        let texturesHeap = try makeTexturesHeap(from: Array(textureMap.values))
        if let texturesHeap {
            textureMap = try convertHeapTexture(from: textureMap, use: texturesHeap)
        }

        let meshCount = extractAllMeshCounts(from: asset)
        let vertexBuffers = extractAllMeshVertexBuffer(from: asset)
        let vertexHeap = try makeVertexHeap(from: meshCount, vertexBuffers: vertexBuffers)
        let fragmentHeap = try makeFragmentHeap(from: meshCount)

        var pbrMeshes: [PBRMesh] = []
        for i in 0..<asset.count {
            let rootObj = asset.object(at: i)
            let meshes = try await loadRecursiveMeshes(
                device: device,
                obj: rootObj,
                textureMap: textureMap,
                vertexHeap: vertexHeap,
                fragmentHeap: fragmentHeap,
                parentTransform: simd_float4x4(1)
            )
            pbrMeshes.append(contentsOf: meshes)
        }

        return PBRMeshContainer(
            meshes: pbrMeshes,
            vertexResources: [vertexHeap],
            fragmentResources: [texturesHeap, fragmentHeap].compactMap { $0 }
        )
    }

    private func loadRecursiveMeshes(
        device: MTLDevice,
        obj: MDLObject,
        textureMap: [MDLTexture: MTLTexture],
        vertexHeap: MTLHeap,
        fragmentHeap: MTLHeap,
        parentTransform: simd_float4x4
    ) async throws -> [PBRMesh] {
        var pbrMeshes: [PBRMesh] = []

        let transform = parentTransform * (obj.transform?.matrix ?? simd_float4x4(1))

        if let mdlMesh = obj as? MDLMesh {
            let mtkMesh = try MTKMesh(mesh: mdlMesh, device: device)

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
                let materialUniformsBuffer = try shaderConnection.moveResourcesToHeap(
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

            var model = transform
            let tmpModelBuffer = device.makeBuffer(
                bytes: &model,
                length: MemoryLayout<float4x4>.size
            )!
            let modelBuffer = try shaderConnection.moveResourcesToHeap(
                from: tmpModelBuffer,
                use: vertexHeap
            )

            let vertexBuffer = try shaderConnection.moveResourcesToHeap(
                from: mtkMesh.vertexBuffers[0].buffer,
                use: vertexHeap
            )

            let pbrMesh = PBRMesh(
                vertexBuffer: vertexBuffer,
                modelBuffer: modelBuffer,
                modelMatrix: model,
                submeshes: submeshes,
            )
            pbrMeshes.append(pbrMesh)
        }

        for childObj in obj.children.objects {
            let childMeshes = try await loadRecursiveMeshes(
                device: device,
                obj: childObj,
                textureMap: textureMap,
                vertexHeap: vertexHeap,
                fragmentHeap: fragmentHeap,
                parentTransform: transform
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

        guard let fragmentArgumentHeap = device.makeHeap(descriptor: heapDescriptor) else {
            throw SwiftGLTFError.makeRender(.fragmentArgumentHeapCreateFailed, context: .capture(stage: .render))
        }
        return fragmentArgumentHeap
    }

    func makeVertexHeap(from meshCount: Int, vertexBuffers: [MDLMeshBuffer]) throws -> MTLHeap {
        let heapDescriptor = MTLHeapDescriptor()

        let modelSize = device.heapBufferSizeAndAlign(length: MemoryLayout<float4x4>.size).alignedSize * meshCount

        var bufferSize: Int = 0
        for vertexBuffer in vertexBuffers {
            let size = device.heapBufferSizeAndAlign(length: vertexBuffer.length).alignedSize
            bufferSize += size
        }

        heapDescriptor.size = modelSize + bufferSize
        heapDescriptor.storageMode = .private

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
