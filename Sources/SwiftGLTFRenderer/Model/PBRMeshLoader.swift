import MetalKit
import Accelerate
import os.log
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
        sceneIndex: Int? = nil,
        animationIndex: Int = 0
    ) throws -> PBRMeshBundle {
        #if DEBUG
        let startTime = Date()
        defer {
            let elapsed = Date().timeIntervalSince(startTime)
            os_log("⏳ PBRMeshLoader: Loaded in %{public}.2f seconds", log: .default, type: .info, elapsed)
        }
        #endif

        let defaultSceneIndex = asset.objectSafe(atPath: GLTFAssetPath.scenes)?.component(ofType: GLTFDefaultScene.self)?.index ?? 0
        let sceneIndex = sceneIndex ?? defaultSceneIndex
        guard let scene = asset.objectSafe(atPath: GLTFAssetPath.scene(sceneIndex)) else {
            throw SwiftGLTFError.render(.sceneNotFound, context: .capture(stage: .render), underlying: nil)
        }
        let nodeLevelHierarchy = makeNodeLevelHierarchy(root: scene)
        let worldTransformsBuffer = try shaderConnection.computeWorldMatrices(nodeLevelHierarchy: nodeLevelHierarchy)

        let skinJoints: [NodeHierarchyOffset] = makeSkinJoints(from: asset, with: nodeLevelHierarchy)
        let jointsBuffer: MTLBuffer
        if !skinJoints.isEmpty {
            jointsBuffer = device.makeBuffer(
                bytes: skinJoints,
                length: MemoryLayout<Int>.size * skinJoints.count,
                options: .storageModeShared
            )!
        } else {
            var dummy = [0]
            jointsBuffer = device.makeBuffer(
                bytes: &dummy,
                length: MemoryLayout<Int>.size,
                options: .storageModeShared
            )!
        }
        let skinDispatchMap: [GLTFSkin: SkinDispatch] = extractSkinDispatchMap(from: asset, with: nodeLevelHierarchy)

        let inverseBindMatrices: [float4x4] = makeSkinInverseBindMatrices(from: asset)
        var inverseBindMatricesBuffer: MTLBuffer
        if !inverseBindMatrices.isEmpty {
            inverseBindMatricesBuffer = device.makeBuffer(
                bytes: inverseBindMatrices,
                length: MemoryLayout<float4x4>.size * inverseBindMatrices.count,
                options: .storageModeShared
            )!
        } else {
            var dummy = [float4x4(1)]
            inverseBindMatricesBuffer = device.makeBuffer(
                bytes: &dummy,
                length: MemoryLayout<float4x4>.size,
                options: .storageModeShared
            )!
        }

        var morphWeights: [Float] = makeMorphWeights(from: asset, with: nodeLevelHierarchy)
        let morphWeightsBuffer: MTLBuffer
        if !morphWeights.isEmpty {
            morphWeightsBuffer = device.makeBuffer(
                bytes: morphWeights,
                length: MemoryLayout<Float>.size * morphWeights.count,
                options: .storageModeShared
            )!
        } else {
            var dummy: [Float] = [0]
            morphWeights = dummy
            morphWeightsBuffer = device.makeBuffer(
                bytes: &dummy,
                length: MemoryLayout<Float>.size,
                options: .storageModeShared
            )!
        }
        let morphDispatches: [MorphDispatch] = makeMorphDispatches(from: asset, with: nodeLevelHierarchy)
        let morphDispatchesBuffer = device.makeBuffer(
            bytes: morphDispatches,
            length: MemoryLayout<MorphDispatch>.size * morphDispatches.count,
            options: .storageModeShared
        )!
        let morphDispatchMap: [MDLObject: MorphDispatch] = extractMorphDispatchMap(from: asset, with: nodeLevelHierarchy)

        let pbrAnimations = makeAnimations(
            from: asset,
            with: nodeLevelHierarchy,
            animationIndex: animationIndex
        )

        let vertexMeshHeap = try makeVertexMeshHeap(from: asset)
        let meshVertexBufferMap = try extractMeshVertexBufferMap(from: asset, use: vertexMeshHeap)

        var textureMap = try extractAllTextureMap(from: asset)
        let texturesHeap = try makeTexturesHeap(from: Array(textureMap.values))
        if let texturesHeap {
            textureMap = try convertHeapTexture(from: textureMap, use: texturesHeap)
        }

        let fragmentHeap = try makeFragmentHeap(from: asset, sceneIndex: sceneIndex)

        let nodes = asset.object(atPath: GLTFAssetPath.nodes(atScene: sceneIndex))
        let pbrMeshes = try loadRecursiveMeshes(
            device: device,
            obj: nodes,
            meshVertexBufferMap: meshVertexBufferMap,
            textureMap: textureMap,
            skinDispatchMap: skinDispatchMap,
            morphDispatchMap: morphDispatchMap,
            fragmentHeap: fragmentHeap,
            parentTransform: float4x4(1),
            nodeLevelHierarchy: nodeLevelHierarchy
        )

        let boundingSpheresBuffer = try shaderConnection.computeBoundingSpheres(meshes: pbrMeshes)

        return PBRMeshBundle(
            meshes: pbrMeshes,
            opaqueMeshes: pbrMeshes.filter { $0.renderingType == .opaque },
            maskedMeshes: pbrMeshes.filter { $0.renderingType == .masked },
            blendedMeshes: pbrMeshes.filter { $0.renderingType == .blended },
            transmissionMeshes: pbrMeshes.filter { $0.renderingType == .transmission },
            worldTransformBuffer: worldTransformsBuffer,
            jointsBuffer: jointsBuffer,
            inverseBindMatricesBuffer: inverseBindMatricesBuffer,
            morphWeightsBuffer: morphWeightsBuffer,
            morphDispatchesBuffer: morphDispatchesBuffer,
            boundingSpheresBuffer: boundingSpheresBuffer,
            animations: pbrAnimations,
            nodeLevelHierarchy: nodeLevelHierarchy,
            originMorphWeights: morphWeights,
            morphDispatches: morphDispatches,
            vertexResources: pbrMeshes.flatMap({ $0.vertexResources }).compactMap({ $0 }),
            vertexHeaps: [vertexMeshHeap].compactMap({ $0 }),
            fragmentHeaps: [texturesHeap, fragmentHeap].compactMap({ $0 }),
        )
    }

    private func loadRecursiveMeshes(
        device: MTLDevice,
        obj: MDLObject,
        meshVertexBufferMap: [MDLMesh: MTLBuffer],
        textureMap: [MDLTexture: MTLTexture],
        skinDispatchMap: [GLTFSkin: SkinDispatch],
        morphDispatchMap: [MDLObject: MorphDispatch],
        fragmentHeap: MTLHeap,
        parentTransform: float4x4,
        nodeLevelHierarchy: NodeLevelHierarchy
    ) throws -> [PBRMesh] {
        var pbrMeshes: [PBRMesh] = []

        let selfTransform = obj.transform?.matrix ?? simd_float4x4(1)
        let totalTransform = parentTransform * selfTransform

        let skinDispatch: SkinDispatch
        if let skin = obj.component(ofType: GLTFSkeletonRef.self)?.skeleton {
            skinDispatch = skinDispatchMap[skin] ?? SkinDispatch(offset: -1, length: 0)
        } else {
            skinDispatch = SkinDispatch(offset: -1, length: 0)
        }

        if let gltfMesh = obj.component(ofType: GLTFMesh.self) {
            for mdlMesh in gltfMesh.primitives {
                let pbrMesh = try makePBRMesh(
                    device: device,
                    obj: obj,
                    mdlMesh: mdlMesh,
                    fragmentHeap: fragmentHeap,
                    meshVertexBufferMap: meshVertexBufferMap,
                    textureMap: textureMap,
                    totalTransform: totalTransform,
                    skinDispatch: skinDispatch,
                    nodeLevelHierarchy: nodeLevelHierarchy
                )
                pbrMeshes.append(pbrMesh)
            }
        }

        for childObj in obj.children.objects {
            let childMeshes = try loadRecursiveMeshes(
                device: device,
                obj: childObj,
                meshVertexBufferMap: meshVertexBufferMap,
                textureMap: textureMap,
                skinDispatchMap: skinDispatchMap,
                morphDispatchMap: morphDispatchMap,
                fragmentHeap: fragmentHeap,
                parentTransform: totalTransform,
                nodeLevelHierarchy: nodeLevelHierarchy
            )
            pbrMeshes.append(contentsOf: childMeshes)
        }

        return pbrMeshes
    }

    private func makePBRMesh(
        device: MTLDevice,
        obj: MDLObject,
        mdlMesh: MDLMesh,
        fragmentHeap: MTLHeap,
        meshVertexBufferMap: [MDLMesh: MTLBuffer],
        textureMap: [MDLTexture: MTLTexture],
        totalTransform: float4x4,
        skinDispatch: SkinDispatch?,
        nodeLevelHierarchy: NodeLevelHierarchy
    ) throws -> PBRMesh {
        let mtkMesh = try MTKMesh(mesh: mdlMesh, device: device)

        guard let vertexBuffer = meshVertexBufferMap[mdlMesh] else {
            throw SwiftGLTFError.render(
                .meshCreationFailed,
                context: .capture(stage: .render),
                underlying: nil
            )
        }

        // Model & Inverse Model matrix buffers
        var model = totalTransform
        var inverseModel = model.inverse
        let modelBuffer = device.makeBuffer(length: MemoryLayout<float4x4>.size)!
        modelBuffer.contents().copyMemory(from: &model, byteCount: MemoryLayout<float4x4>.size)
        let inverseModelBuffer = device.makeBuffer(length: MemoryLayout<float4x4>.size)!
        inverseModelBuffer.contents().copyMemory(from: &inverseModel, byteCount: MemoryLayout<float4x4>.size)

        // Morph data detection on this mesh
        var morphCount: UInt32 = 0
        var morphWeightsBuffer: MTLBuffer? = nil
        var morphTargetBuffers: [MTLBuffer] = []
        if let morphComp = mdlMesh.component(ofType: GLTFMorphTargets.self) {
            morphCount = UInt32(morphComp.targetCount)
            morphWeightsBuffer = device.makeBuffer(length: MemoryLayout<Float>.size * morphComp.targetCount)!
            morphWeightsBuffer!.contents().copyMemory(from: morphComp.defaultWeights, byteCount: MemoryLayout<Float>.size * morphComp.targetCount)

            // Convert target MDLMesh -> MTLBuffer (vertex buffer 0)
            for targetMDL in morphComp.targetMeshes.prefix(8) { // Limit to max 8
                if let vb = meshVertexBufferMap[targetMDL] {
                    morphTargetBuffers.append(vb)
                } else {
                    os_log("⚠️ Warning: Morph target mesh not found in vertex map.", log: .default, type: .error)
                }
            }
        }

        let transformIndex: Int = nodeLevelHierarchy.objectToIndex[ObjectIdentifier(obj)] ?? -1
        let morphDispatchIndex: Int = transformIndex

        // Create vertex argument buffer
        let vertexArgumentBuffer = try pipelineConnector.makeVertexArgumentsBuffer(
            modelBuffer: modelBuffer,
            inverseModelBuffer: inverseModelBuffer,
            morphTargetCount: morphCount,
            morphWeightsBuffer: morphWeightsBuffer,
            morphInterleavedBuffers: morphTargetBuffers,
            transformIndex: transformIndex,
            skinDispatch: skinDispatch,
            morphDispatchIndex: morphDispatchIndex
        )

        // Process submeshes
        var hasTransmission = false
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

            // Transmission texture and sampler (KHR_materials_transmission)
            var (hasTransmissionTexture, transmissionTexture, transmissionSamplerState) = retrieveTexture(prop: material?.propertyNamed(.transmissionTexture), textureMap: textureMap)
            // Thickness texture and sampler (KHR_materials_volume)
            var (hasThicknessTexture, thicknessTexture, thicknessSamplerState) = retrieveTexture(prop: material?.propertyNamed(.thicknessTexture), textureMap: textureMap)
            // Specular textures (KHR_materials_specular)
            var (hasSpecularTexture, specularTexture, specularSamplerState) = retrieveTexture(prop: material?.propertyNamed(.specularTexture), textureMap: textureMap)
            var (hasSpecularColorTexture, specularColorTexture, specularColorSamplerState) = retrieveTexture(prop: material?.propertyNamed(.specularColorTexture), textureMap: textureMap)

            // Sheen textures
            var (hasSheenColorTexture, sheenColorTexture, sheenColorSamplerState) = retrieveTexture(prop: material?.propertyNamed(.sheenColorTexture), textureMap: textureMap)
            var (hasSheenRoughnessTexture, sheenRoughnessTexture, sheenRoughnessSamplerState) = retrieveTexture(prop: material?.propertyNamed(.sheenRoughnessTexture), textureMap: textureMap)

            // Clearcoat textures
            var (hasClearcoatTexture, clearcoatTexture, clearcoatSamplerState) = retrieveTexture(prop: material?.propertyNamed(.clearcoatTexture), textureMap: textureMap)
            var (hasClearcoatRoughnessTexture, clearcoatRoughnessTexture, clearcoatRoughnessSamplerState) = retrieveTexture(prop: material?.propertyNamed(.clearcoatRoughnessTexture), textureMap: textureMap)
            var (hasClearcoatNormalTexture, clearcoatNormalTexture, clearcoatNormalSamplerState) = retrieveTexture(prop: material?.propertyNamed(.clearcoatNormalTexture), textureMap: textureMap)

            let baseColorTransform = textureTransform(material: material, offsetScaleName: .baseColorTextureTransformOffsetScale, rotationName: .baseColorTextureTransformRotation)
            let normalTransform = textureTransform(material: material, offsetScaleName: .normalTextureTransformOffsetScale, rotationName: .normalTextureTransformRotation)
            let metallicRoughnessTransform = textureTransform(material: material, offsetScaleName: .metallicRoughnessTextureTransformOffsetScale, rotationName: .metallicRoughnessTextureTransformRotation)
            let emissiveTransform = textureTransform(material: material, offsetScaleName: .emissiveTextureTransformOffsetScale, rotationName: .emissiveTextureTransformRotation)
            let occlusionTransform = textureTransform(material: material, offsetScaleName: .occlusionTextureTransformOffsetScale, rotationName: .occlusionTextureTransformRotation)
            let transmissionTransform = textureTransform(material: material, offsetScaleName: .transmissionTextureTransformOffsetScale, rotationName: .transmissionTextureTransformRotation)
            let thicknessTransform = textureTransform(material: material, offsetScaleName: .thicknessTextureTransformOffsetScale, rotationName: .thicknessTextureTransformRotation)
            let specularTransform = textureTransform(material: material, offsetScaleName: .specularTextureTransformOffsetScale, rotationName: .specularTextureTransformRotation)
            let specularColorTransform = textureTransform(material: material, offsetScaleName: .specularColorTextureTransformOffsetScale, rotationName: .specularColorTextureTransformRotation)
            let sheenColorTransform = textureTransform(material: material, offsetScaleName: .sheenColorTextureTransformOffsetScale, rotationName: .sheenColorTextureTransformRotation)
            let sheenRoughnessTransform = textureTransform(material: material, offsetScaleName: .sheenRoughnessTextureTransformOffsetScale, rotationName: .sheenRoughnessTextureTransformRotation)
            let clearcoatTransform = textureTransform(material: material, offsetScaleName: .clearcoatTextureTransformOffsetScale, rotationName: .clearcoatTextureTransformRotation)
            let clearcoatRoughnessTransform = textureTransform(material: material, offsetScaleName: .clearcoatRoughnessTextureTransformOffsetScale, rotationName: .clearcoatRoughnessTextureTransformRotation)
            let clearcoatNormalTransform = textureTransform(material: material, offsetScaleName: .clearcoatNormalTextureTransformOffsetScale, rotationName: .clearcoatNormalTextureTransformRotation)

            var baseColorTransformOffsetScale = baseColorTransform.offsetScale
            var baseColorTransformRotation = baseColorTransform.rotation
            var normalTransformOffsetScale = normalTransform.offsetScale
            var normalTransformRotation = normalTransform.rotation
            var metallicRoughnessTransformOffsetScale = metallicRoughnessTransform.offsetScale
            var metallicRoughnessTransformRotation = metallicRoughnessTransform.rotation
            var emissiveTransformOffsetScale = emissiveTransform.offsetScale
            var emissiveTransformRotation = emissiveTransform.rotation
            var occlusionTransformOffsetScale = occlusionTransform.offsetScale
            var occlusionTransformRotation = occlusionTransform.rotation
            var transmissionTransformOffsetScale = transmissionTransform.offsetScale
            var transmissionTransformRotation = transmissionTransform.rotation
            var thicknessTransformOffsetScale = thicknessTransform.offsetScale
            var thicknessTransformRotation = thicknessTransform.rotation
            var specularTransformOffsetScale = specularTransform.offsetScale
            var specularTransformRotation = specularTransform.rotation
            var specularColorTransformOffsetScale = specularColorTransform.offsetScale
            var specularColorTransformRotation = specularColorTransform.rotation
            var sheenColorTransformOffsetScale = sheenColorTransform.offsetScale
            var sheenColorTransformRotation = sheenColorTransform.rotation
            var sheenRoughnessTransformOffsetScale = sheenRoughnessTransform.offsetScale
            var sheenRoughnessTransformRotation = sheenRoughnessTransform.rotation
            var clearcoatTransformOffsetScale = clearcoatTransform.offsetScale
            var clearcoatTransformRotation = clearcoatTransform.rotation
            var clearcoatRoughnessTransformOffsetScale = clearcoatRoughnessTransform.offsetScale
            var clearcoatRoughnessTransformRotation = clearcoatRoughnessTransform.rotation
            var clearcoatNormalTransformOffsetScale = clearcoatNormalTransform.offsetScale
            var clearcoatNormalTransformRotation = clearcoatNormalTransform.rotation

            // Retrieve texture coordinate indices and cast to UInt32
            let baseColorTexCoordF: Float = material?.propertyNamed(.baseColorTextureTexCoord)?.floatValue ?? 0.0
            let normalTexCoordF: Float = material?.propertyNamed(.normalTextureTexCoord)?.floatValue ?? 0.0
            let metalRoughnessTexCoordF: Float = material?.propertyNamed(.metallicRoughnessTextureTexCoord)?.floatValue ?? 0.0
            let emissiveTexCoordF: Float = material?.propertyNamed(.emissiveTextureTexCoord)?.floatValue ?? 0.0
            let occlusionTexCoordF: Float = material?.propertyNamed(.occlusionTextureTexCoord)?.floatValue ?? 0.0
            let transmissionTexCoordF: Float = material?.propertyNamed(.transmissionTextureTexCoord)?.floatValue ?? 0.0
            let thicknessTexCoordF: Float = material?.propertyNamed(.thicknessTextureTexCoord)?.floatValue ?? 0.0
            let specularTexCoordF: Float = material?.propertyNamed(.specularTextureTexCoord)?.floatValue ?? 0.0
            let specularColorTexCoordF: Float = material?.propertyNamed(.specularColorTextureTexCoord)?.floatValue ?? 0.0
            let sheenColorTexCoordF: Float = material?.propertyNamed(.sheenColorTextureTexCoord)?.floatValue ?? 0.0
            let sheenRoughnessTexCoordF: Float = material?.propertyNamed(.sheenRoughnessTextureTexCoord)?.floatValue ?? 0.0
            let clearcoatTexCoordF: Float = material?.propertyNamed(.clearcoatTextureTexCoord)?.floatValue ?? 0.0
            let clearcoatRoughnessTexCoordF: Float = material?.propertyNamed(.clearcoatRoughnessTextureTexCoord)?.floatValue ?? 0.0
            let clearcoatNormalTexCoordF: Float = material?.propertyNamed(.clearcoatNormalTextureTexCoord)?.floatValue ?? 0.0
            var baseColorTexCoord: UInt32 = UInt32(baseColorTexCoordF)
            var normalTexCoord: UInt32 = UInt32(normalTexCoordF)
            var metalRoughnessTexCoord: UInt32 = UInt32(metalRoughnessTexCoordF)
            var emissiveTexCoord: UInt32 = UInt32(emissiveTexCoordF)
            var occlusionTexCoord: UInt32 = UInt32(occlusionTexCoordF)
            var transmissionTexCoord: UInt32 = UInt32(transmissionTexCoordF)
            var thicknessTexCoord: UInt32 = UInt32(thicknessTexCoordF)
            var specularTexCoord: UInt32 = UInt32(specularTexCoordF)
            var specularColorTexCoord: UInt32 = UInt32(specularColorTexCoordF)
            var sheenColorTexCoord: UInt32 = UInt32(sheenColorTexCoordF)
            var sheenRoughnessTexCoord: UInt32 = UInt32(sheenRoughnessTexCoordF)
            var clearcoatTexCoord: UInt32 = UInt32(clearcoatTexCoordF)
            var clearcoatRoughnessTexCoord: UInt32 = UInt32(clearcoatRoughnessTexCoordF)
            var clearcoatNormalTexCoord: UInt32 = UInt32(clearcoatNormalTexCoordF)

            // Alpha mode & cutoff
            let alphaModeStr = material?.propertyNamed(.alphaMode)?.stringValue?.uppercased() ?? "OPAQUE"
            let alphaModeEnum: SwiftGLTFShaderTypes.AlphaMode = {
                switch alphaModeStr {
                case "MASK": return AlphaModeMask
                case "BLEND": return AlphaModeBlend
                default: return AlphaModeOpaque
                }
            }()
            var alphaModeRaw: UInt32 = alphaModeEnum.rawValue
            var alphaCutoff: Float = material?.propertyNamed(.alphaCutoff)?.floatValue ?? 0.5

            // Transmission factor
            let transmissionFactor: Float = material?.propertyNamed(.transmissionFactor)?.floatValue ?? 0.0
            hasTransmission = transmissionFactor > 0 || hasTransmissionTexture

            // Double sided flag
            let isDoubleSided: Bool = (material?.propertyNamed(.doubleSided)?.floatValue ?? 0) != 0

            // Create material uniforms buffer
            let attenuationDistance: Float = {
                if let v = material?.propertyNamed(.attenuationDistance)?.floatValue { return v }
                return -1.0 // <= 0 means infinity (no attenuation)
            }()
            let attenuationColor: SIMD3<Float> = material?.propertyNamed(.attenuationColor)?.float3Value ?? SIMD3<Float>(1, 1, 1)
            let ior: Float = material?.propertyNamed(.ior)?.floatValue ?? 1.5
            let specularFactor: Float = material?.propertyNamed(.specularFactor)?.floatValue ?? 1.0
            let specularColorFactor: SIMD3<Float> = material?.propertyNamed(.specularColorFactor)?.float3Value ?? SIMD3<Float>(1, 1, 1)
            let sheenColorFactor: SIMD3<Float> = material?.propertyNamed(.sheenColorFactor)?.float3Value ?? SIMD3<Float>(0, 0, 0)
            let sheenRoughnessFactor: Float = material?.propertyNamed(.sheenRoughnessFactor)?.floatValue ?? 0.0
            let clearcoatFactor: Float = material?.propertyNamed(.clearcoatFactor)?.floatValue ?? 0.0
            let clearcoatRoughnessFactor: Float = material?.propertyNamed(.clearcoatRoughnessFactor)?.floatValue ?? 0.0
            let clearcoatNormalScale: Float = material?.propertyNamed(.clearcoatNormalTextureScale)?.floatValue ?? 1.0
            var clearcoatNormalScaleValue = clearcoatNormalScale
            let clearcoatFactors = SIMD4<Float>(clearcoatFactor, clearcoatRoughnessFactor, clearcoatNormalScale, 0)

            var materialUniforms = PBRMaterialUniforms(
                baseColorFactor: baseColorFactor,
                metalRoughnessOcclusion: SIMD4<Float>(metallicFactor, roughnessFactor, occlusionFactor, 0),
                emissiveFactor: SIMD4<Float>(emissiveFactor.x, emissiveFactor.y, emissiveFactor.z, 0),
                doubleSided: isDoubleSided ? 1 : 0,
                transmissionThicknessDistance: SIMD4<Float>(transmissionFactor, material?.propertyNamed(.thicknessFactor)?.floatValue ?? 0.0, attenuationDistance, 0),
                attenuationColor: SIMD4<Float>(attenuationColor.x, attenuationColor.y, attenuationColor.z, 0),
                ior: ior,
                specularFactor: specularFactor,
                specularFactorColor: SIMD4<Float>(specularColorFactor.x, specularColorFactor.y, specularColorFactor.z, 0),
                sheenColorRoughness: SIMD4<Float>(sheenColorFactor.x, sheenColorFactor.y, sheenColorFactor.z, sheenRoughnessFactor),
                clearcoatFactors: clearcoatFactors
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
                // Transmission/Thickness
                hasTransmissionTexture: &hasTransmissionTexture,
                transmissionTexture: transmissionTexture,
                transmissionSampler: transmissionSamplerState,
                transmissionTexCoord: &transmissionTexCoord,
                hasThicknessTexture: &hasThicknessTexture,
                thicknessTexture: thicknessTexture,
                thicknessSampler: thicknessSamplerState,
                thicknessTexCoord: &thicknessTexCoord,
                // Specular
                hasSpecularTexture: &hasSpecularTexture,
                specularTexture: specularTexture,
                specularSampler: specularSamplerState,
                specularTexCoord: &specularTexCoord,
                hasSpecularColorTexture: &hasSpecularColorTexture,
                specularColorTexture: specularColorTexture,
                specularColorSampler: specularColorSamplerState,
                specularColorTexCoord: &specularColorTexCoord,
                // Sheen
                hasSheenColorTexture: &hasSheenColorTexture,
                sheenColorTexture: sheenColorTexture,
                sheenColorSampler: sheenColorSamplerState,
                sheenColorTexCoord: &sheenColorTexCoord,
                hasSheenRoughnessTexture: &hasSheenRoughnessTexture,
                sheenRoughnessTexture: sheenRoughnessTexture,
                sheenRoughnessSampler: sheenRoughnessSamplerState,
                sheenRoughnessTexCoord: &sheenRoughnessTexCoord,
                // Clearcoat
                hasClearcoatTexture: &hasClearcoatTexture,
                clearcoatTexture: clearcoatTexture,
                clearcoatSampler: clearcoatSamplerState,
                clearcoatTexCoord: &clearcoatTexCoord,
                hasClearcoatRoughnessTexture: &hasClearcoatRoughnessTexture,
                clearcoatRoughnessTexture: clearcoatRoughnessTexture,
                clearcoatRoughnessSampler: clearcoatRoughnessSamplerState,
                clearcoatRoughnessTexCoord: &clearcoatRoughnessTexCoord,
                hasClearcoatNormalTexture: &hasClearcoatNormalTexture,
                clearcoatNormalTexture: clearcoatNormalTexture,
                clearcoatNormalSampler: clearcoatNormalSamplerState,
                clearcoatNormalTexCoord: &clearcoatNormalTexCoord,
                clearcoatNormalScale: &clearcoatNormalScaleValue,
                // Alpha params
                alphaMode: &alphaModeRaw,
                alphaCutoff: &alphaCutoff,
                baseColorTransformOffsetScale: &baseColorTransformOffsetScale,
                baseColorTransformRotation: &baseColorTransformRotation,
                normalTransformOffsetScale: &normalTransformOffsetScale,
                normalTransformRotation: &normalTransformRotation,
                metallicRoughnessTransformOffsetScale: &metallicRoughnessTransformOffsetScale,
                metallicRoughnessTransformRotation: &metallicRoughnessTransformRotation,
                emissiveTransformOffsetScale: &emissiveTransformOffsetScale,
                emissiveTransformRotation: &emissiveTransformRotation,
                occlusionTransformOffsetScale: &occlusionTransformOffsetScale,
                occlusionTransformRotation: &occlusionTransformRotation,
                transmissionTransformOffsetScale: &transmissionTransformOffsetScale,
                transmissionTransformRotation: &transmissionTransformRotation,
                thicknessTransformOffsetScale: &thicknessTransformOffsetScale,
                thicknessTransformRotation: &thicknessTransformRotation,
                specularTransformOffsetScale: &specularTransformOffsetScale,
                specularTransformRotation: &specularTransformRotation,
                specularColorTransformOffsetScale: &specularColorTransformOffsetScale,
                specularColorTransformRotation: &specularColorTransformRotation,
                sheenColorTransformOffsetScale: &sheenColorTransformOffsetScale,
                sheenColorTransformRotation: &sheenColorTransformRotation,
                sheenRoughnessTransformOffsetScale: &sheenRoughnessTransformOffsetScale,
                sheenRoughnessTransformRotation: &sheenRoughnessTransformRotation,
                clearcoatTransformOffsetScale: &clearcoatTransformOffsetScale,
                clearcoatTransformRotation: &clearcoatTransformRotation,
                clearcoatRoughnessTransformOffsetScale: &clearcoatRoughnessTransformOffsetScale,
                clearcoatRoughnessTransformRotation: &clearcoatRoughnessTransformRotation,
                clearcoatNormalTransformOffsetScale: &clearcoatNormalTransformOffsetScale,
                clearcoatNormalTransformRotation: &clearcoatNormalTransformRotation
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
                    occlusionSamplerState,
                    transmissionTexture,
                    transmissionSamplerState,
                    thicknessTexture,
                    thicknessSamplerState,
                    specularTexture,
                    specularSamplerState,
                    specularColorTexture,
                    specularColorSamplerState,
                    sheenColorTexture,
                    sheenColorSamplerState,
                    sheenRoughnessTexture,
                    sheenRoughnessSamplerState,
                    clearcoatTexture,
                    clearcoatSamplerState,
                    clearcoatRoughnessTexture,
                    clearcoatRoughnessSamplerState,
                    clearcoatNormalTexture,
                    clearcoatNormalSamplerState
                ]
            )
            submeshes.append(submeshData)
        }

        // Decide rendering type based on submeshes
        let renderingType: PBRMesh.RenderingType = {
            if hasTransmission {
                return .transmission
            }
            if submeshes.contains(where: { $0.alphaMode == AlphaModeBlend }) {
                return .blended
            }
            if submeshes.contains(where: { $0.alphaMode == AlphaModeMask }) {
                return .masked
            }
            return .opaque
        }()

        // POSITION 属性のレイアウト情報
        let mdlVD = mdlMesh.vertexDescriptor
        let positionAttr = (mdlVD.attributes as? [MDLVertexAttribute])?.first(where: { $0.name == MDLVertexAttributePosition })
        let positionBufferIndex = positionAttr?.bufferIndex ?? 0
        let positionOffset = positionAttr?.offset ?? 0
        let positionStride = (mdlVD.layouts[positionBufferIndex] as? MDLVertexBufferLayout)?.stride ?? 0

        let pbrMesh = PBRMesh(
            vertexBuffer: vertexBuffer,
            vertexArgumentBuffer: vertexArgumentBuffer,
            submeshes: submeshes,
            modelMatrix: model,
            transformIndex: transformIndex,
            vertexCount: mtkMesh.vertexCount,
            positionStride: positionStride,
            positionOffset: positionOffset,
            renderingType: renderingType,
            vertexResources: [
                morphWeightsBuffer,
                modelBuffer,
                inverseModelBuffer
            ],
            _storedHeapInstance: morphTargetBuffers
        )
        return pbrMesh
    }

    func makeSkinJoints(from asset: MDLAsset, with nodeLevelHierarchy: NodeLevelHierarchy) -> [NodeHierarchyOffset] {
        var skinJoints: [NodeHierarchyOffset] = []

        for joint in asset.skins.flatMap({ $0.jointObjects }) {
            let oid = ObjectIdentifier(joint)
            if let index = nodeLevelHierarchy.objectToIndex[oid] {
                skinJoints.append(index)
            } else {
                os_log("⚠️ Warning: Joint node %s not found in node hierarchy.", log: .default, type: .error, joint.name)
            }
        }

        return skinJoints
    }

    func makeSkinInverseBindMatrices(from asset: MDLAsset) -> [float4x4] {
        var inverseBindMatrices: [float4x4] = []

        for skin in asset.skins {
            inverseBindMatrices.append(contentsOf: skin.inverseBindMatrices.float4x4Array)
        }

        return inverseBindMatrices
    }

    func makeMorphWeights(from asset: MDLAsset, with nodeLevelHierarchy: NodeLevelHierarchy) -> [Float] {
        var morphWeights: [Float] = []

        for index in nodeLevelHierarchy.levelNodes {
            let obj = nodeLevelHierarchy.indexToObject[index]
            if let morph = obj.component(ofType: GLTFMorphWeights.self) {
                morphWeights.append(contentsOf: morph.weights)
            }
        }

        return morphWeights
    }

    func makeMorphDispatches(from asset: MDLAsset, with nodeLevelHierarchy: NodeLevelHierarchy) -> [MorphDispatch] {
        var morphDispatches: [MorphDispatch] = []

        var offset: Int64 = 0
        for index in nodeLevelHierarchy.levelNodes {
            let obj = nodeLevelHierarchy.indexToObject[index]
            if let morph = obj.component(ofType: GLTFMorphWeights.self) {
                let length = Int64(morph.weights.count)
                morphDispatches.append(MorphDispatch(offset: offset, length: length))
                offset += length
            } else {
                morphDispatches.append(MorphDispatch(offset: offset, length: 0))
            }
        }

        return morphDispatches
    }

    func makeAnimations(
        from asset: MDLAsset,
        with nodeLevelHierarchy: NodeLevelHierarchy,
        animationIndex: Int
    ) -> [PBRMeshAnimation] {
        guard let gltfAnimation = asset.animations as? GLTFAnimationContainer else { return [] }
        guard gltfAnimation.objects.count > animationIndex else { return [] }
        guard let anim = gltfAnimation.objects[animationIndex].component(ofType: GLTFAnimation.self) else { return [] }

        var pbrAnimations: [PBRMeshAnimation] = []
        for channel in anim.channels {
            guard let targetNode = nodeLevelHierarchy.objectToIndex[ObjectIdentifier(channel.targetNode)] else {
                os_log("⚠️ Warning: Animation target node %s not found in node hierarchy.", log: .default, type: .error, channel.targetNode.name)
                continue
            }
            let pbrAnim = PBRMeshAnimation(
                targetNode: targetNode,
                type: channel.type,
                keyframes: channel.input,
                duration: anim.duration,
                interpolation: channel.interpolation
            )
            pbrAnimations.append(pbrAnim)
        }
        return pbrAnimations
    }

    func extractSkinDispatchMap(from asset: MDLAsset, with nodeLevelHierarchy: NodeLevelHierarchy) -> [GLTFSkin: SkinDispatch] {
        var skinDispatchMap: [GLTFSkin: SkinDispatch] = [:]

        var offset: Int64 = 0
        for skin in asset.skins {
            let length = Int64(skin.jointObjects.count)
            skinDispatchMap[skin] = SkinDispatch(
                offset: offset,
                length: length
            )
            offset += length
        }

        return skinDispatchMap
    }

    func extractMeshVertexBufferMap(from asset: MDLAsset, use vertexMeshHeap: MTLHeap) throws -> [MDLMesh: MTLBuffer] {
        var meshVertexBufferMap: [MDLMesh: MTLBuffer] = [:]

        for mesh in asset.gltfMeshes {
            let mtkMesh = try MTKMesh(mesh: mesh, device: device)
            let vertexBuffer = try shaderConnection.moveBufferToHeap(
                from: mtkMesh.vertexBuffers[0].buffer,
                use: vertexMeshHeap
            )
            meshVertexBufferMap[mesh] = vertexBuffer

            if let morph = mesh.componentConforming(to: GLTFMorphTargets.self) as? GLTFMorphTargets {
                for targetMDL in morph.targetMeshes {
                    let mtkTarget = try MTKMesh(mesh: targetMDL, device: device)
                    let heapBuf = try shaderConnection.moveBufferToHeap(
                        from: mtkTarget.vertexBuffers[0].buffer,
                        use: vertexMeshHeap
                    )
                    meshVertexBufferMap[targetMDL] = heapBuf
                }
            }
        }

        return meshVertexBufferMap
    }

    func extractAllTextureMap(from asset: MDLAsset) throws -> [MDLTexture: MTLTexture] {
        var textureMap: [MDLTexture: MTLTexture] = [:]
        var needConvertionLinearSpace: [MDLTexture: MTLTexture] = [:]

        for mesh in asset.gltfMeshes {
            for submesh in mesh.submeshes ?? [] {
                guard let mdlSubmesh = submesh as? MDLSubmesh, let material = mdlSubmesh.material else { continue }
                for propertyIndex in 0..<material.count {
                    guard let property = material[propertyIndex], property.type == .texture,
                          let texture = property.textureSamplerValue?.texture else { continue }
                    let mtlTexture = try mdl2mtlTexture(texture)
                    textureMap[texture] = mtlTexture

                    if property.name == MaterialPropertyName.emissiveTexture.rawValue ||
                        property.name == MaterialPropertyName.baseColorTexture.rawValue ||
                        property.name == MaterialPropertyName.specularColorTexture.rawValue ||
                        property.name == MaterialPropertyName.sheenColorTexture.rawValue {
                        needConvertionLinearSpace[texture] = mtlTexture
                    }
                }
            }
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

    func extractMorphDispatchMap(from asset: MDLAsset, with nodeLevelHierarchy: NodeLevelHierarchy) -> [MDLObject: MorphDispatch] {
        var morphDispatchMap: [MDLObject: MorphDispatch] = [:]

        var offset: Int64 = 0
        for index in nodeLevelHierarchy.levelNodes {
            let obj = nodeLevelHierarchy.indexToObject[index]
            if let morph = obj.component(ofType: GLTFMorphWeights.self) {
                morphDispatchMap[obj] = MorphDispatch(
                    offset: offset,
                    length: Int64(morph.weights.count)
                )
                offset += Int64(morph.weights.count)
            } else {
                // No morph on this node
                morphDispatchMap[obj] = MorphDispatch(
                    offset: -1,
                    length: 0
                )
            }
        }

        return morphDispatchMap
    }

    func extractDrawingCount(from asset: MDLAsset, sceneIndex: Int) -> Int {
        var drawingCount = 0

        func traverse(object: MDLObject) {
            if let gltfMesh = object.component(ofType: GLTFMesh.self) {
                for mesh in gltfMesh.primitives {
                    drawingCount += mesh.submeshes?.count ?? 0
                }
            }

            for child in object.children.objects {
                traverse(object: child)
            }
        }

        let scene = asset.object(atPath: GLTFAssetPath.scene(sceneIndex))
        traverse(object: scene)

        return drawingCount
    }

    func extractAllMeshVertexBuffer(from asset: MDLAsset) -> [MDLMeshBuffer] {
        var buffers: [MDLMeshBuffer] = []

        for mesh in asset.gltfMeshes {
            buffers.append(contentsOf: mesh.vertexBuffers)
        }

        return buffers
    }

    func extractAllMorphVertexBuffer(from asset: MDLAsset) -> [MDLMeshBuffer] {
        var buffers: [MDLMeshBuffer] = []

        for mesh in asset.gltfMeshes {
            if let morph = mesh.componentConforming(to: GLTFMorphTargets.self) as? GLTFMorphTargets {
                for target in morph.targetMeshes {
                    if let buf = target.vertexBuffers.first { buffers.append(buf) }
                }
            }
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

    func makeFragmentHeap(from asset: MDLAsset, sceneIndex: Int) throws -> MTLHeap {
        let drawingCount = extractDrawingCount(from: asset, sceneIndex: sceneIndex)
        let size = device.heapBufferSizeAndAlign(length: MemoryLayout<PBRMaterialUniforms>.size).alignedSize

        let heapDescriptor = MTLHeapDescriptor()
        heapDescriptor.size = size * drawingCount
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
        heapDescriptor.storageMode = .shared

        guard heapDescriptor.size > 0 else { return nil }
        guard let skeletonHeap = device.makeHeap(descriptor: heapDescriptor) else {
            return nil
        }
        return skeletonHeap
    }

    func makeVertexMeshHeap(from asset: MDLAsset) throws -> MTLHeap {
        let vertexBuffers = extractAllMeshVertexBuffer(from: asset)
        let morphVertexBuffers = extractAllMorphVertexBuffer(from: asset)

        var bufferSize: Int = 0
        for vertexBuffer in vertexBuffers + morphVertexBuffers {
            let size = device.heapBufferSizeAndAlign(length: vertexBuffer.length).alignedSize
            bufferSize += size
        }

        let heapDescriptor = MTLHeapDescriptor()
        heapDescriptor.size = bufferSize
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

    // MARK: - Texture & Sampler Helpers

    private func textureTransform(material: MDLMaterial?, offsetScaleName: MaterialPropertyName, rotationName: MaterialPropertyName) -> TextureTransformParameters {
        guard let offsetScaleProperty = material?.propertyNamed(offsetScaleName) else {
            return .identity
        }
        let offsetScale = offsetScaleProperty.float4Value
        let rotation = material?.propertyNamed(rotationName)?.floatValue ?? 0.0
        return TextureTransformParameters(offsetScale: offsetScale, rotation: rotation)
    }

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

    func buffer2float4x4Array(_ buffer: MTLBuffer) -> [float4x4] {
        let capacity = buffer.length / MemoryLayout<float4x4>.size
        let pointer = buffer.contents().bindMemory(to: float4x4.self, capacity: capacity)
        let bufferPointer = UnsafeBufferPointer(start: pointer, count: capacity)
        return Array(bufferPointer)
    }
}
