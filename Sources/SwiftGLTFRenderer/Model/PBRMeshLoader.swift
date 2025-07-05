import MetalKit
import Accelerate

struct MDLAssetLoaderPipelineStateConfig {
    let pnucVertexShader: MTLFunction
    let pnucFragmentShader: MTLFunction
    let pntuVertexShader: MTLFunction
    let pntuFragmentShader: MTLFunction
    let pnuVertexShader: MTLFunction
    let pnuFragmentShader: MTLFunction
    let pnVertexShader: MTLFunction
    let pnFragmentShader: MTLFunction
    let puVertexShader: MTLFunction
    let puFragmentShader: MTLFunction
    let pVertexShader: MTLFunction
    let pFragmentShader: MTLFunction
    let sampleCount: Int
}

class PBRMeshLoader {
    let asset: MDLAsset
    let shaderConnection: ShaderConnection
    let pipelineStateConfig: MDLAssetLoaderPipelineStateConfig

    private var texturesCache: [String: MTLTexture] = [:]

    init(
        asset: MDLAsset,
        shaderConnection: ShaderConnection,
        pipelineStateConfig: MDLAssetLoaderPipelineStateConfig
    ) {
        self.asset = asset
        self.shaderConnection = shaderConnection
        self.pipelineStateConfig = pipelineStateConfig
    }

    func loadMeshes(device: MTLDevice) throws -> [PBRMesh] {
        var pbrMeshes: [PBRMesh] = []

        for i in 0..<asset.count {
            let rootObj = asset.object(at: i)
            let meshes = try loadRecursiveMeshes(
                device: device,
                obj: rootObj,
                psoConfig: pipelineStateConfig,
                parentTransform: simd_float4x4(1)
            )
            pbrMeshes.append(contentsOf: meshes)
        }

        return pbrMeshes
    }

    private func makeSamplerState(from sampler: MDLTextureSampler?, device: MTLDevice) -> MTLSamplerState? {
        guard let sampler = sampler else { return nil }

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

        return device.makeSamplerState(descriptor: descriptor)
    }

    private func loadRecursiveMeshes(
        device: MTLDevice,
        obj: MDLObject,
        psoConfig: MDLAssetLoaderPipelineStateConfig,
        parentTransform: simd_float4x4
    ) throws -> [PBRMesh] {
        var pbrMeshes: [PBRMesh] = []

        let transform = parentTransform * (obj.transform?.matrix ?? simd_float4x4(1))

        if let mdlMesh = obj as? MDLMesh {
            let mtkMesh = try MTKMesh(mesh: mdlMesh, device: device)

            var submeshes: [PBRMesh.Submesh] = []
            for (mtkSubmesh, mdlSubmesh) in zip(mtkMesh.submeshes, mdlMesh.submeshes as! [MDLSubmesh]) {
                // Load a base color texture and sampler
                // TODO: Multiple base color texture to color factor
                let baseColorTexUrl: URL? = mdlSubmesh.material?.property(with: .baseColor)?.urlValue
                let baseColorSampler: MDLTextureSampler = {
                    if let s = mdlSubmesh.material?.property(with: .baseColor)?.textureSamplerValue {
                        return s
                    } else {
                        let color = mdlSubmesh.material?.property(with: .baseColor)?.float3Value ?? SIMD3<Float>(1, 1, 1)
                        let floatPixels: [Float16] = [Float16(color.x), Float16(color.y), Float16(color.z), 1.0]
                        return makeDummySampler(textureValue: floatPixels, channelCount: 4, channelEncoding: .float16)
                    }
                }()
                var baseColorTexture: MTLTexture?
                if let tex = baseColorSampler.texture {
                    let shouldConvertedToLinear: Bool = if let url = baseColorTexUrl {
                        isLinearColorSpace(from: url) == false
                    } else {
                        false
                    }
                    baseColorTexture = try convertTextureWithCache(tex, convertLinearColorSpace: shouldConvertedToLinear, device: device)
                }
                let baseColorSamplerState = makeSamplerState(from: baseColorSampler, device: device)

                // Load a normal texture and sampler
                let normalSampler: MDLTextureSampler = {
                    if let s = mdlSubmesh.material?.property(with: .tangentSpaceNormal)?.textureSamplerValue {
                        return s
                    } else {
                        let floatPixels: [Float16] = [0.5, 0.5, 1.0, 1.0]
                        return makeDummySampler(textureValue: floatPixels, channelCount: 4, channelEncoding: .float16)
                    }
                }()
                var normalTexture: MTLTexture?
                if let tex = normalSampler.texture {
                    normalTexture = try convertTextureWithCache(tex, device: device)
                }
                let normalSamplerState = makeSamplerState(from: normalSampler, device: device)

                // Make material properties
                let metallicFactor: Float = mdlSubmesh.material?.property(with: .metallic)?.floatValue ?? 1.0
                let roughnessFactor: Float = mdlSubmesh.material?.property(with: .roughness)?.floatValue ?? 1.0
                let metallicRoughnessMDLSampler = {
                    if let s = mdlSubmesh.material?.propertyNamed("metallicRoughnessTexture")?.textureSamplerValue {
                        return s
                    } else {
                        let metallicRoughness: [Float16] = [0, 1, 1, 0]
                        return makeDummySampler(textureValue: metallicRoughness, channelCount: 4, channelEncoding: .float16)
                    }
                }()

                var metallicRoughnessTexture: MTLTexture?
                var metallicRoughnessSamplerState: MTLSamplerState?
                if let tex = try metallicRoughnessMDLSampler.texture?.imageFromTexture(device: device) {
                    metallicRoughnessTexture = try shaderConnection.makeMetallicRoughnessTexture(
                        metallicFactor: metallicFactor,
                        roughnessFactor: roughnessFactor,
                        baseMetallicRoughnessTexture: tex
                    )
                    metallicRoughnessSamplerState = makeSamplerState(from: metallicRoughnessMDLSampler, device: device)
                }

                let emissiveSampler: MDLTextureSampler = {
                    if let s = mdlSubmesh.material?.property(with: .emission)?.textureSamplerValue {
                        return s
                    } else {
                        let emissive: [Float16] = [1, 1, 1, 1]
                        return makeDummySampler(textureValue: emissive, channelCount: 4, channelEncoding: .float16)
                    }
                }()
                var emissiveTexture: MTLTexture?
                var emissiveSamplerState: MTLSamplerState?
                if let tex = try emissiveSampler.texture?.imageFromTexture(device: device, convertLinearColorSpace: true) {
                    emissiveTexture = try shaderConnection.makeEmissiveTexture(
                        emissiveFactor: mdlSubmesh.material?.property(with: .emission)?.float3Value ?? SIMD3<Float>(0, 0, 0),
                        emissiveTexture: tex
                    )
                    emissiveSamplerState = makeSamplerState(from: emissiveSampler, device: device)
                }

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
                    emissiveSampler: emissiveSamplerState
                )
                submeshes.append(submeshData)
            }

            let (vertexShader, fragmentShader) = try decideShader(from: mtkMesh.vertexDescriptor)

            let psoDescriptor = MTLRenderPipelineDescriptor()
            psoDescriptor.vertexFunction = vertexShader
            psoDescriptor.fragmentFunction = fragmentShader
            psoDescriptor.colorAttachments[0].pixelFormat = .rgba16Float
            psoDescriptor.depthAttachmentPixelFormat = .depth32Float
            psoDescriptor.rasterSampleCount = psoConfig.sampleCount
            psoDescriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(mtkMesh.vertexDescriptor)
            let pso = try device.makeRenderPipelineState(descriptor: psoDescriptor)

            let pbrMesh = PBRMesh(
                vertexBuffer: mtkMesh.vertexBuffers[0].buffer,
                submeshes: submeshes,
                pso: pso,
                transform: transform,
                modelBuffer: device.makeBuffer(
                    length: MemoryLayout<float4x4>.size,
                    options: []
                )!,
                normalMatrixBuffer: device.makeBuffer(
                    length: MemoryLayout<float3x3>.size,
                    options: []
                )!
            )
            pbrMeshes.append(pbrMesh)
        }

        for childObj in obj.children.objects {
            let childMeshes = try loadRecursiveMeshes(
                device: device,
                obj: childObj,
                psoConfig: psoConfig,
                parentTransform: transform
            )
            pbrMeshes.append(contentsOf: childMeshes)
        }

        return pbrMeshes
    }

    private func decideShader(from vertexDescriptor: MDLVertexDescriptor) throws -> (MTLFunction, MTLFunction) {
        var existingPosition: Bool = false
        var existingNormal: Bool = false
        var existingTangent: Bool = false
        var existingModulationColor: Bool = false
        var existingTextureCoordinate: Bool = false

        for attr in vertexDescriptor.attributes {
            if let attr = attr as? MDLVertexAttribute {
                if attr.name == MDLVertexAttributePosition {
                    existingPosition = true
                }
                if attr.name == MDLVertexAttributeNormal {
                    existingNormal = true
                }
                if attr.name == MDLVertexAttributeTangent {
                    existingTangent = true
                }
                if attr.name == MDLVertexAttributeColor {
                    existingModulationColor = true
                }
                if attr.name == MDLVertexAttributeTextureCoordinate {
                    existingTextureCoordinate = true
                }
            }
        }

        if existingPosition && existingNormal && existingModulationColor && existingTextureCoordinate {
            os_log("Using PNUC shaders")
            return (pipelineStateConfig.pnucVertexShader, pipelineStateConfig.pnucFragmentShader)
        } else if existingPosition && existingNormal && existingTextureCoordinate && existingTangent {
            os_log("Using PNTU shaders")
            return (pipelineStateConfig.pntuVertexShader, pipelineStateConfig.pntuFragmentShader)
        } else if existingPosition && existingNormal && existingTextureCoordinate {
            os_log("Using PNU shaders")
            return (pipelineStateConfig.pnuVertexShader, pipelineStateConfig.pnuFragmentShader)
        } else if existingPosition && existingNormal {
            os_log("Using PN shaders")
            return (pipelineStateConfig.pnVertexShader, pipelineStateConfig.pnFragmentShader)
        } else if existingPosition && existingTextureCoordinate {
            os_log("Using PU shaders")
            return (pipelineStateConfig.puVertexShader, pipelineStateConfig.puFragmentShader)
        } else if existingPosition {
            os_log("Using P shaders")
            return (pipelineStateConfig.pVertexShader, pipelineStateConfig.pFragmentShader)
        } else {
            throw NSError(
                domain: "MDLAssetLoader",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unsupported vertex descriptor"]
            )
        }
    }

    private func convertTextureWithCache(
        _ tex: MDLTexture,
        convertLinearColorSpace: Bool = false,
        device: MTLDevice
    ) throws -> MTLTexture {
        if let cachedTexture = texturesCache[tex.name] {
            return cachedTexture
        } else {
            let mtkTex: MTLTexture = try tex.imageFromTexture(device: device, convertLinearColorSpace: convertLinearColorSpace)
            if !tex.name.isEmpty {
                texturesCache[tex.name] = mtkTex
            }
            return mtkTex
        }
    }
}

extension MDLTexture {
    func imageFromTexture(device: MTLDevice, convertLinearColorSpace: Bool = false) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor()
        descriptor.pixelFormat = switch channelCount {
        case 1: .r32Float
        case 2: .rg32Float
        // case 3: TODO: No suitable format exists for MTLPixelFormat
        case 4: .rgba32Float
        default: throw NSError(domain: "MDLTexture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unsupported channel count"])
        }
        descriptor.width = Int(self.dimensions.x)
        descriptor.height = Int(self.dimensions.y)
        descriptor.usage = [.shaderRead]

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw NSError(
                domain: "MDLTexture",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create texture"]
            )
        }

        let region = MTLRegionMake2D(0, 0, Int(self.dimensions.x), Int(self.dimensions.y))
        guard let texelData = self.texelDataWithTopLeftOrigin() else {
            throw NSError(
                domain: "MDLTexture",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Failed to get texel data"]
            )
        }

        let channelCount = Int(self.channelCount)
        let pixelCount = Int(self.dimensions.x * self.dimensions.y)
        let floatPixelCount = pixelCount * channelCount
        var floatPixels = [Float](repeating: 0, count: floatPixelCount)

        switch self.channelEncoding {
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

        let bytesPerRow = channelCount * MemoryLayout<Float>.size * Int(self.dimensions.x)
        floatPixels.withUnsafeBytes { ptr in
            texture.replace(
                region: region,
                mipmapLevel: 0,
                withBytes: ptr.baseAddress!,
                bytesPerRow: bytesPerRow
            )
        }

        if convertLinearColorSpace {
            return try convertSrgb2Linear(texture)
        } else {
            return texture
        }
    }


    func convertUInt8ToFloat(_ src: [UInt8]) -> [Float] {
        let count = src.count
        var float32Array = [Float](repeating: 0, count: count)

        vDSP_vfltu8(src, 1, &float32Array, 1, vDSP_Length(count))
        var scale: Float = 1.0 / 255.0
        var outArray = [Float](repeating: 0, count: count)
        vDSP_vsmul(&float32Array, 1, &scale, &outArray, 1, vDSP_Length(count))

        return outArray
    }

    func convertUInt16ToFloat(_ src: [UInt16]) -> [Float] {
        let count = src.count
        var float32Array = [Float](repeating: 0, count: count)

        vDSP_vfltu16(src, 1, &float32Array, 1, vDSP_Length(count))
        var scale: Float = 1.0 / 65535.0
        var outArray = [Float](repeating: 0, count: count)
        vDSP_vsmul(&float32Array, 1, &scale, &outArray, 1, vDSP_Length(count))

        return outArray
    }

    func convertFloat16ToFloat32_vImage(_ input: [Float16]) -> [Float] {
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
}

private func convertSrgb2Linear(_ texture: MTLTexture) throws -> MTLTexture {
    let outputTextureDescriptor = MTLTextureDescriptor()
    outputTextureDescriptor.pixelFormat = .rgba32Float
    outputTextureDescriptor.width = texture.width
    outputTextureDescriptor.height = texture.height
    outputTextureDescriptor.usage = [.shaderRead, .shaderWrite]
    guard let outputTexture = texture.device.makeTexture(descriptor: outputTextureDescriptor) else {
        throw NSError(
            domain: "MDLAssetLoader",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Failed to create output texture"]
        )
    }

    guard let convertShader = try texture.device.makeDefaultLibrary(bundle: Bundle.module).makeFunction(name: "texture_srgb_2_linear_shader") else {
        throw NSError(
            domain: "MDLAssetLoader",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Failed to create convert shader"]
        )
    }
    let pso = try texture.device.makeComputePipelineState(function: convertShader)

    let commandQueue = texture.device.makeCommandQueue()!
    let commandBuffer = commandQueue.makeCommandBuffer()!
    let computeEncoder = commandBuffer.makeComputeCommandEncoder()!
    computeEncoder.setComputePipelineState(pso)
    computeEncoder.setTexture(texture, index: 0)
    computeEncoder.setTexture(outputTexture, index: 1)
    let threadsPerThreadgroup = MTLSize(width: 16, height: 16, depth: 1)
    let threadgroups = MTLSize(
        width: (texture.width + threadsPerThreadgroup.width - 1) / threadsPerThreadgroup.width,
        height: (texture.height + threadsPerThreadgroup.height - 1) / threadsPerThreadgroup.height,
        depth: 1
    )
    computeEncoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
    computeEncoder.endEncoding()
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
    return outputTexture
}


private func isLinearColorSpace(from url: URL) -> Bool? {
    guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else {
        return nil
    }

    let options: [CFString: Any] = [
        kCGImageSourceShouldCache: true // 必要に応じてキャッシュ
    ]
    if let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, options as CFDictionary) {
        switch cgImage.colorSpace?.name {
        case CGColorSpace.linearSRGB,
            CGColorSpace.linearGray,
            CGColorSpace.linearDisplayP3,
            CGColorSpace.linearITUR_2020,
            CGColorSpace.acescgLinear,
            CGColorSpace.genericRGBLinear,
            CGColorSpace.extendedLinearGray,
            CGColorSpace.extendedLinearSRGB,
            CGColorSpace.extendedLinearDisplayP3,
            CGColorSpace.extendedLinearITUR_2020:
            return true
        default:
            return false
        }
    } else {
        return nil
    }
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
