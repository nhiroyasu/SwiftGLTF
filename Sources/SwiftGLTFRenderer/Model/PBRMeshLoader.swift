import MetalKit
import Accelerate
import SwiftGLTF

class PBRMeshLoader {
    let shaderConnection: ShaderConnection
    let pipelineStateLoader: PBRPipelineStateLoader
    let depthStencilStateLoader: DepthStencilStateLoader

    // TODO: Consider using a more sophisticated caching mechanism
    private var texturesCache: [String: MTLTexture] = [:]

    init(
        shaderConnection: ShaderConnection,
        pipelineStateLoader: PBRPipelineStateLoader,
        depthStencilStateLoader: DepthStencilStateLoader
    ) {
        self.shaderConnection = shaderConnection
        self.pipelineStateLoader = pipelineStateLoader
        self.depthStencilStateLoader = depthStencilStateLoader
    }

    func loadMeshes(from asset: MDLAsset, using device: MTLDevice) throws -> [PBRMesh] {
        texturesCache = [:]

        var pbrMeshes: [PBRMesh] = []
        for i in 0..<asset.count {
            let rootObj = asset.object(at: i)
            let meshes = try loadRecursiveMeshes(
                device: device,
                obj: rootObj,
                parentTransform: simd_float4x4(1)
            )
            pbrMeshes.append(contentsOf: meshes)
        }

        return pbrMeshes
    }

    private func makeSamplerState(from sampler: MDLTextureSampler, device: MTLDevice) throws -> MTLSamplerState {
        let descriptor = MTLSamplerDescriptor()

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
            throw NSError(
                domain: "MDLAssetLoader",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create sampler state"]
            )
        }
    }

    private func loadRecursiveMeshes(
        device: MTLDevice,
        obj: MDLObject,
        parentTransform: simd_float4x4
    ) throws -> [PBRMesh] {
        var pbrMeshes: [PBRMesh] = []

        let transform = parentTransform * (obj.transform?.matrix ?? simd_float4x4(1))

        if let mdlMesh = obj as? MDLMesh {
            let mtkMesh = try MTKMesh(mesh: mdlMesh, device: device)

            var submeshes: [PBRMesh.Submesh] = []
            for (mtkSubmesh, mdlSubmesh) in zip(mtkMesh.submeshes, mdlMesh.submeshes as! [MDLSubmesh]) {
                // Base color texture and sampler
                let (baseColorTexture, baseColorSamplerState) = try makeBaseColorTextureAndSampler(device: device, material: mdlSubmesh.material)

                // Normal texture and sampler
                let (normalTexture, normalSamplerState) = try makeNormalTextureAndSampler(device: device, material: mdlSubmesh.material)

                // Make metallic roughness texture and sampler
                let (metallicRoughnessTexture, metallicRoughnessSamplerState) = try makeMetallicRoughnessTextureAndSampler(device: device, material: mdlSubmesh.material)

                // Make emissive texture and sampler
                let (emissiveTexture, emissiveSamplerState) = try makeEmissiveTextureAndSampler(device, mdlSubmesh.material)

                // Occlusion texture and sampler
                let (occlusionTexture, occlusionSamplerState) = try makeOcclusionTextureAndSampler(device: device, material: mdlSubmesh.material)

                let submeshData = PBRMesh.Submesh(
                    primitiveType: mtkSubmesh.primitiveType,
                    indexCount: mtkSubmesh.indexCount,
                    indexType: mtkSubmesh.indexType,
                    indexBuffer: mtkSubmesh.indexBuffer,
                    baseColorTexture: baseColorTexture,
                    baseColorSampler: baseColorSamplerState,
                    normalTexture: normalTexture,
                    normalSampler: normalSamplerState,
                    metallicRoughnessTexture: metallicRoughnessTexture,
                    metallicRoughnessSampler: metallicRoughnessSamplerState,
                    emissiveTexture: emissiveTexture,
                    emissiveSampler: emissiveSamplerState,
                    occlusionTexture: occlusionTexture,
                    occlusionSampler: occlusionSamplerState
                )
                submeshes.append(submeshData)
            }

            var model = transform

            let pbrMesh = PBRMesh(
                vertexBuffer: mtkMesh.vertexBuffers[0].buffer,
                vertexUniformsBuffer: try makeVertexUniformsBuffer(
                    mdlMesh.vertexDescriptor,
                    device: device
                ),
                submeshes: submeshes,
                modelBuffer: device.makeBuffer(
                    bytes: &model,
                    length: MemoryLayout<float4x4>.size
                )!,
                pso: try pipelineStateLoader.load(for: mtkMesh.vertexDescriptor),
                dso: try depthStencilStateLoader.load(for: .lessThan)
            )
            pbrMeshes.append(pbrMesh)
        }

        for childObj in obj.children.objects {
            let childMeshes = try loadRecursiveMeshes(
                device: device,
                obj: childObj,
                parentTransform: transform
            )
            pbrMeshes.append(contentsOf: childMeshes)
        }

        return pbrMeshes
    }

    private func convertTextureWithCache(
        _ mdlTex: MDLTexture,
        convertLinearColorSpace: Bool = false,
        device: MTLDevice
    ) throws -> MTLTexture {
        if let cachedTexture = texturesCache[mdlTex.name] {
            return cachedTexture
        } else {
            let mtkTex: MTLTexture = try mdl2mtlTexture(mdlTex, device: device, convertLinearColorSpace: convertLinearColorSpace)
            if !mdlTex.name.isEmpty {
                texturesCache[mdlTex.name] = mtkTex
            }
            return mtkTex
        }
    }

    // MARK: - Texture & Sampler Helpers

    private func makeBaseColorTextureAndSampler(device: MTLDevice, material: MDLMaterial?) throws -> (MTLTexture, MTLSamplerState) {
        let prop = material?.propertyNamed(.baseColorTexture)
        let factorProp = material?.propertyNamed(.baseColorFactor)

        let sampler: MDLTextureSampler
        if let s = prop?.textureSamplerValue {
            sampler = s
        } else {
            sampler = makeDummySampler(textureValue: Array<Float16>(repeating: 1, count: 4), channelCount: 4, channelEncoding: .float16)
        }

        guard let tex = sampler.texture else {
            throw NSError(
                domain: "MDLAssetLoader",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Base color texture not found"]
            )
        }
        let color = factorProp?.float4Value ?? SIMD4<Float>(1, 1, 1, 1)
        var texture = try convertTextureWithCache(tex, convertLinearColorSpace: true, device: device)
        texture = try shaderConnection.makeBaseColorTexture(baseColorFactor: color, baseColorTexture: texture)

        let samplerState = try makeSamplerState(from: sampler, device: device)

        return (texture, samplerState)
    }

    private func makeNormalTextureAndSampler(device: MTLDevice, material: MDLMaterial?) throws -> (MTLTexture, MTLSamplerState) {
        let sampler: MDLTextureSampler
        if let s = material?.propertyNamed(.normalTexture)?.textureSamplerValue {
            sampler = s
        } else {
            sampler = makeDummySampler(textureValue: [Float16(0.5), 0.5, 1.0, 1.0], channelCount: 4, channelEncoding: .float16)
        }

        let texture: MTLTexture
        if let mdlTex = sampler.texture {
            texture = try mdl2mtlTexture(mdlTex, device: device)
        } else {
            throw NSError(
                domain: "MDLAssetLoader",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Normal texture not found"]
            )
        }

        let samplerState = try makeSamplerState(from: sampler, device: device)

        return (texture, samplerState)
    }

    private func makeMetallicRoughnessTextureAndSampler(device: MTLDevice, material: MDLMaterial?) throws -> (MTLTexture, MTLSamplerState) {
        let metallicRoughnessTextureProp = material?.propertyNamed(.metallicRoughnessTexture)
        let metallicFactorProp = material?.propertyNamed(.metallic)
        let roughnessFactorProp = material?.propertyNamed(.roughness)

        let metallicRoughnessMDLSampler = if let mdlSampler = metallicRoughnessTextureProp?.textureSamplerValue {
            mdlSampler
        } else {
            makeDummySampler(
                textureValue: Array<Float16>([0, 1, 1, 0]),
                channelCount: 4,
                channelEncoding: .float16
            )
        }

        let tex: MTLTexture
        if let mdlTex = metallicRoughnessMDLSampler.texture {
            tex = try mdl2mtlTexture(mdlTex, device: device)
        } else {
            throw NSError(
                domain: "MDLAssetLoader",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Metallic roughness texture not found"]
            )
        }

        let metallicFactor = metallicFactorProp?.floatValue ?? 1.0
        let roughnessFactor = roughnessFactorProp?.floatValue ?? 1.0
        let texture = try shaderConnection.makeMetallicRoughnessTexture(
            metallicFactor: metallicFactor,
            roughnessFactor: roughnessFactor,
            baseMetallicRoughnessTexture: tex
        )

        let samplerState = try makeSamplerState(from: metallicRoughnessMDLSampler, device: device)

        return (texture, samplerState)
    }

    private func makeOcclusionTextureAndSampler(device: MTLDevice, material: MDLMaterial?) throws -> (MTLTexture, MTLSamplerState) {
        let sampler: MDLTextureSampler
        if let s = material?.propertyNamed(.occlusion)?.textureSamplerValue {
            sampler = s
        } else {
            sampler = makeDummySampler(textureValue: [Float16(1), 0, 0, 0], channelCount: 4, channelEncoding: .float16)
        }

        let tex: MTLTexture
        if let mdlTex = sampler.texture {
            tex = try mdl2mtlTexture(mdlTex, device: device)
        } else {
            throw NSError(
                domain: "MDLAssetLoader",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Ambient occlusion texture not found"]
            )
        }
        let factor = material?.propertyNamed(.occlusionStrength)?.floatValue ?? 1.0
        let texture = try shaderConnection.makeOcclusionTexture(occlusionFactor: factor, occlusionTexture: tex)

        let samplerState = try makeSamplerState(from: sampler, device: device)
        return (texture, samplerState)
    }

    private func makeEmissiveTextureAndSampler(_ device: MTLDevice, _ material: MDLMaterial?) throws -> (MTLTexture, MTLSamplerState) {
        let emissiveTextureProp = material?.propertyNamed(.emissiveTexture)
        let emissiveFactorProp = material?.propertyNamed(.emissiveFactor)

        let emissiveSampler: MDLTextureSampler = if let mdlSampler = emissiveTextureProp?.textureSamplerValue {
            mdlSampler
        } else {
            makeDummySampler(
                textureValue: Array<Float16>([1, 1, 1, 1]),
                channelCount: 4,
                channelEncoding: .float16
            )
        }

        let tex: MTLTexture
        if let mdlTex = emissiveSampler.texture {
            tex = try mdl2mtlTexture(mdlTex, device: device, convertLinearColorSpace: true)
        } else {
            throw NSError(
                domain: "MDLAssetLoader",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to load emissive texture"]
            )
        }
        let emissiveTexture = try shaderConnection.makeEmissiveTexture(
            emissiveFactor: emissiveFactorProp?.float3Value ?? SIMD3<Float>(0, 0, 0),
            emissiveTexture: tex
        )
        let emissiveSamplerState = try makeSamplerState(from: emissiveSampler, device: device)

        return (emissiveTexture, emissiveSamplerState)
    }

    private func mdl2mtlTexture(
        _ mdlTexture: MDLTexture,
        device: MTLDevice,
        convertLinearColorSpace: Bool = false
    ) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor()
        descriptor.pixelFormat = switch mdlTexture.channelCount {
        case 1: .r32Float
        case 2: .rg32Float
        // case 3: TODO: No suitable format exists for MTLPixelFormat
        case 4: .rgba32Float
        default: throw NSError(domain: "MDLTexture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unsupported channel count"])
        }
        descriptor.width = Int(mdlTexture.dimensions.x)
        descriptor.height = Int(mdlTexture.dimensions.y)
        descriptor.usage = [.shaderRead]

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw NSError(
                domain: "MDLTexture",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create texture"]
            )
        }

        let region = MTLRegionMake2D(0, 0, Int(mdlTexture.dimensions.x), Int(mdlTexture.dimensions.y))
        guard let texelData = mdlTexture.texelDataWithBottomLeftOrigin() else {
            throw NSError(
                domain: "MDLTexture",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Failed to get texel data"]
            )
        }

        let channelCount = Int(mdlTexture.channelCount)
        let pixelCount = Int(mdlTexture.dimensions.x * mdlTexture.dimensions.y)
        let floatPixelCount = pixelCount * channelCount
        var floatPixels = [Float](repeating: 0, count: floatPixelCount)

        switch mdlTexture.channelEncoding {
        case .uint8:
            let src = texelData.withUnsafeBytes { rawBufferPointer in
                let floatBufferPointer = rawBufferPointer.bindMemory(to: UInt8.self)
                return Array(floatBufferPointer)
            }
            floatPixels = convertUInt8ToFloat(src)
        case .uint16:
            let src = texelData.withUnsafeBytes { rawBufferPointer in
                let floatBufferPointer = rawBufferPointer.bindMemory(to: UInt16.self)
                return Array(floatBufferPointer)
            }
            floatPixels = convertUInt16ToFloat(src)
        case .float16:
            let src = texelData.withUnsafeBytes { rawBufferPointer in
                let floatBufferPointer = rawBufferPointer.bindMemory(to: Float16.self)
                return Array(floatBufferPointer)
            }
            floatPixels = convertFloat16ToFloat32_vImage(src)
        case .float32:
            let src = texelData.withUnsafeBytes { rawBufferPointer in
                let floatBufferPointer = rawBufferPointer.bindMemory(to: Float.self)
                return Array(floatBufferPointer)
            }
            for i in 0..<floatPixelCount {
                floatPixels[i] = src[i]
            }
        default:
            throw NSError(
                domain: "MDLTexture",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Unsupported channel encoding"]
            )
        }

        let bytesPerRow = channelCount * MemoryLayout<Float>.size * Int(mdlTexture.dimensions.x)
        floatPixels.withUnsafeBytes { ptr in
            texture.replace(
                region: region,
                mipmapLevel: 0,
                withBytes: ptr.baseAddress!,
                bytesPerRow: bytesPerRow
            )
        }

        if convertLinearColorSpace {
            return try shaderConnection.convertSrgb2Linear(texture: texture)
        } else {
            return texture
        }
    }

    // MARK: - Vertex Uniforms Buffer

    private func makeVertexUniformsBuffer(
        _ vertexDescriptor: MDLVertexDescriptor,
        device: MTLDevice
    ) throws -> MTLBuffer {
        var vertexUniforms = PBRVertexUniforms(
            hasTangent: vertexDescriptor.validTangentVertex,
            hasUV: vertexDescriptor.validTexcoordVertex,
            hasModulationColor: vertexDescriptor.validColorVertex
        )

        if let buffer = device.makeBuffer(
            bytes: &vertexUniforms,
            length: MemoryLayout<PBRVertexUniforms>.size
        ) {
            return buffer
        } else {
            throw NSError(
                domain: "MDLAssetLoader",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create vertex uniforms buffer"]
            )
        }
    }
}

private func convertUInt8ToFloat(_ src: [UInt8]) -> [Float] {
    let count = src.count
    var float32Array = [Float](repeating: 0, count: count)

    vDSP_vfltu8(src, 1, &float32Array, 1, vDSP_Length(count))
    var scale: Float = 1.0 / 255.0
    var outArray = [Float](repeating: 0, count: count)
    vDSP_vsmul(&float32Array, 1, &scale, &outArray, 1, vDSP_Length(count))

    return outArray
}

private func convertUInt16ToFloat(_ src: [UInt16]) -> [Float] {
    let count = src.count
    var float32Array = [Float](repeating: 0, count: count)

    vDSP_vfltu16(src, 1, &float32Array, 1, vDSP_Length(count))
    var scale: Float = 1.0 / 65535.0
    var outArray = [Float](repeating: 0, count: count)
    vDSP_vsmul(&float32Array, 1, &scale, &outArray, 1, vDSP_Length(count))

    return outArray
}

private func convertFloat16ToFloat32_vImage(_ input: [Float16]) -> [Float] {
    let width = input.count
    var input = input
    var srcBuffer = vImage_Buffer(
        data: input.withUnsafeMutableBytes { $0.baseAddress },
        height: vImagePixelCount(1),
        width: vImagePixelCount(width),
        rowBytes: width * MemoryLayout<Float16>.size
    )

    var dstArray = [Float](repeating: 0, count: input.count)
    var dstBuffer = vImage_Buffer(
        data: dstArray.withUnsafeMutableBytes { $0.baseAddress },
        height: vImagePixelCount(1),
        width: vImagePixelCount(input.count),
        rowBytes: width * MemoryLayout<Float>.size
    )

    let error = vImageConvert_Planar16FtoPlanarF(&srcBuffer, &dstBuffer, 0)
    if error != kvImageNoError {
        print("vImage error: \(error)")
    }

    return dstArray
}

private func makeDummySampler<T: Numeric>(
    textureValue: Array<T>,
    channelCount: Int,
    channelEncoding: MDLTextureChannelEncoding
) -> MDLTextureSampler {
    let sampler = MDLTextureSampler()
    let tex = MDLTexture(
        data: Data(buffer: textureValue.withUnsafeBufferPointer { $0 }),
        topLeftOrigin: true,
        name: nil,
        dimensions: [1, 1],
        rowStride: textureValue.count * MemoryLayout<T>.size,
        channelCount: channelCount,
        channelEncoding: channelEncoding,
        isCube: false
    )
    sampler.texture = tex
    sampler.hardwareFilter?.minFilter = .linear
    sampler.hardwareFilter?.magFilter = .linear
    sampler.hardwareFilter?.sWrapMode = .repeat
    sampler.hardwareFilter?.tWrapMode = .repeat
    return sampler
}
