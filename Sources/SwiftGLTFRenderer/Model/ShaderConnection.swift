import Metal

class ShaderConnection {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue

    init(device: MTLDevice, commandQueue: MTLCommandQueue) {
        self.device = device
        self.commandQueue = commandQueue
    }

    func makeMetallicRoughnessTexture(
        metallicFactor: Float,
        roughnessFactor: Float,
        baseMetallicRoughnessTexture: MTLTexture
    ) throws -> MTLTexture {
        let library = try device.makeDefaultLibrary(bundle: Bundle.module)
        
        guard let computeShader = library.makeFunction(name: "metallic_roughness_texture_shader") else {
            throw NSError(domain: "ShaderConnection", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create metallic roughness shader function"])
        }

        let pso = try device.makeComputePipelineState(function: computeShader)

        let outputTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: baseMetallicRoughnessTexture.width,
            height: baseMetallicRoughnessTexture.height,
            mipmapped: false
        )
        outputTextureDescriptor.usage = [.shaderRead, .shaderWrite]
        guard let outputTexture = device.makeTexture(descriptor: outputTextureDescriptor) else {
            throw NSError(domain: "ShaderConnection", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create output texture"])
        }

        let commandBuffer = commandQueue.makeCommandBuffer()!
        let computeEncoder = commandBuffer.makeComputeCommandEncoder()!
        computeEncoder.setComputePipelineState(pso)

        var metallicFactor = metallicFactor
        var roughnessFactor = roughnessFactor
        let metallicFactorBuffer = device.makeBuffer(
            bytes: &metallicFactor,
            length: MemoryLayout<Float>.size,
            options: []
        )!
        let roughnessFactorBuffer = device.makeBuffer(
            bytes: &roughnessFactor,
            length: MemoryLayout<Float>.size,
            options: []
        )!
        computeEncoder.setBuffer(metallicFactorBuffer, offset: 0, index: 0)
        computeEncoder.setBuffer(roughnessFactorBuffer, offset: 0, index: 1)
        computeEncoder.setTexture(baseMetallicRoughnessTexture, index: 0)
        computeEncoder.setTexture(outputTexture, index: 1)

        let threadsPerThreadgroup = MTLSize(width: 16, height: 16, depth: 1)
        let threadgroups = MTLSize(
            width: (outputTexture.width + threadsPerThreadgroup.width - 1) / threadsPerThreadgroup.width,
            height: (outputTexture.height + threadsPerThreadgroup.height - 1) / threadsPerThreadgroup.height,
            depth: 1
        )
        computeEncoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
        computeEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return outputTexture
    }

    func makeEmissiveTexture(
        emissiveFactor: SIMD3<Float>,
        emissiveTexture: MTLTexture
    ) throws -> MTLTexture {
        let library = try device.makeDefaultLibrary(bundle: Bundle.module)
        guard let computeShader = library.makeFunction(name: "emissive_multiplier_shader") else {
            throw NSError(domain: "ShaderConnection", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create metallic roughness shader function"])
        }

        let pso = try device.makeComputePipelineState(function: computeShader)

        let outputTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: emissiveTexture.width,
            height: emissiveTexture.height,
            mipmapped: false
        )
        outputTextureDescriptor.usage = [.shaderRead, .shaderWrite]
        guard let outputTexture = device.makeTexture(descriptor: outputTextureDescriptor) else {
            throw NSError(domain: "ShaderConnection", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create output texture"])
        }

        let commandBuffer = commandQueue.makeCommandBuffer()!
        let computeEncoder = commandBuffer.makeComputeCommandEncoder()!
        computeEncoder.setComputePipelineState(pso)

        var emissiveFactorFloat4: SIMD4<Float> = SIMD4<Float>(emissiveFactor.x, emissiveFactor.y, emissiveFactor.z, 1.0)
        let emissiveFactorBuffer = device.makeBuffer(
            bytes: &emissiveFactorFloat4,
            length: MemoryLayout<SIMD4<Float>>.size,
            options: []
        )!
        computeEncoder.setBuffer(emissiveFactorBuffer, offset: 0, index: 0)
        computeEncoder.setTexture(emissiveTexture, index: 0)
        computeEncoder.setTexture(outputTexture, index: 1)

        let threadsPerThreadgroup = MTLSize(width: 16, height: 16, depth: 1)
        let threadgroups = MTLSize(
            width: (outputTexture.width + threadsPerThreadgroup.width - 1) / threadsPerThreadgroup.width,
            height: (outputTexture.height + threadsPerThreadgroup.height - 1) / threadsPerThreadgroup.height,
            depth: 1
        )
        computeEncoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
        computeEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return outputTexture
    }

    func makeOcclusionTexture(
        occlusionFactor: Float,
        occlusionTexture: MTLTexture
    ) throws -> MTLTexture {
        let library = try device.makeDefaultLibrary(bundle: Bundle.module)
        guard let computeShader = library.makeFunction(name: "occlusion_multiplier_shader") else {
            throw NSError(domain: "ShaderConnection", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create occlusion shader function"])
        }

        let pso = try device.makeComputePipelineState(function: computeShader)

        let outputTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: occlusionTexture.width,
            height: occlusionTexture.height,
            mipmapped: false
        )
        outputTextureDescriptor.usage = [.shaderRead, .shaderWrite]
        guard let outputTexture = device.makeTexture(descriptor: outputTextureDescriptor) else {
            throw NSError(domain: "ShaderConnection", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create output texture"])
        }

        let commandBuffer = commandQueue.makeCommandBuffer()!
        let computeEncoder = commandBuffer.makeComputeCommandEncoder()!
        computeEncoder.setComputePipelineState(pso)

        var occlusionFactor: Float = occlusionFactor
        let occlusionFactorBuffer = device.makeBuffer(
            bytes: &occlusionFactor,
            length: MemoryLayout<Float>.size,
            options: []
        )!
        computeEncoder.setBuffer(occlusionFactorBuffer, offset: 0, index: 0)
        computeEncoder.setTexture(occlusionTexture, index: 0)
        computeEncoder.setTexture(outputTexture, index: 1)

        let threadsPerThreadgroup = MTLSize(width: 16, height: 16, depth: 1)
        let threadgroups = MTLSize(
            width: (outputTexture.width + threadsPerThreadgroup.width - 1) / threadsPerThreadgroup.width,
            height: (outputTexture.height + threadsPerThreadgroup.height - 1) / threadsPerThreadgroup.height,
            depth: 1
        )
        computeEncoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
        computeEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return outputTexture
    }

    func makeBaseColorTexture(baseColorFactor: SIMD4<Float>, baseColorTexture: MTLTexture) throws -> MTLTexture {
        let library = try device.makeDefaultLibrary(bundle: Bundle.module)

        guard let computeShader = library.makeFunction(name: "base_color_multiplier_shader") else {
            throw NSError(domain: "ShaderConnection", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create base color shader function"])
        }

        let pso = try device.makeComputePipelineState(function: computeShader)

        let outputTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: baseColorTexture.width,
            height: baseColorTexture.height,
            mipmapped: false
        )
        outputTextureDescriptor.usage = [.shaderRead, .shaderWrite]
        guard let outputTexture = device.makeTexture(descriptor: outputTextureDescriptor) else {
            throw NSError(domain: "ShaderConnection", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create output texture"])
        }

        let commandBuffer = commandQueue.makeCommandBuffer()!
        let computeEncoder = commandBuffer.makeComputeCommandEncoder()!
        computeEncoder.setComputePipelineState(pso)

        var baseColorFactorFloat4 = baseColorFactor
        let baseColorFactorBuffer = device.makeBuffer(
            bytes: &baseColorFactorFloat4,
            length: MemoryLayout<SIMD4<Float>>.size,
            options: []
        )!
        computeEncoder.setBuffer(baseColorFactorBuffer, offset: 0, index: 0)
        computeEncoder.setTexture(baseColorTexture, index: 0)
        computeEncoder.setTexture(outputTexture, index: 1)

        let threadsPerThreadgroup = MTLSize(width: 16, height: 16, depth: 1)
        let threadgroups = MTLSize(
            width: (outputTexture.width + threadsPerThreadgroup.width - 1) / threadsPerThreadgroup.width,
            height: (outputTexture.height + threadsPerThreadgroup.height - 1) / threadsPerThreadgroup.height,
            depth: 1
        )
        computeEncoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
        computeEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return outputTexture
    }
}
