import Metal

class ShaderConnection {
    let device: MTLDevice
    let library: MTLLibrary
    let commandQueue: MTLCommandQueue

    init(device: MTLDevice, library: MTLLibrary, commandQueue: MTLCommandQueue) {
        self.device = device
        self.library = library
        self.commandQueue = commandQueue
    }

    func convertSrgb2Linear(textures: [MTLTexture]) throws -> [MTLTexture] {
        let commandBuffer = commandQueue.makeCommandBuffer()!
        guard let convertShader = library.makeFunction(name: "texture_srgb_2_linear_shader") else {
            throw NSError(
                domain: "MDLAssetLoader",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create convert shader"]
            )
        }
        let pso = try device.makeComputePipelineState(function: convertShader)

        var output: [MTLTexture] = []
        for texture in textures {
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

            output.append(outputTexture)
        }

        commandBuffer.commit()
        return output
    }

    func moveResourceToHeap(
        from texture: MTLTexture,
        use heap: MTLHeap
    ) throws -> MTLTexture {
        let results = try moveResourcesToHeap(from: [texture], use: heap)
        guard let firstTexture = results.first else {
            throw NSError(domain: "ShaderConnection", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to move texture to heap"])
        }
        return firstTexture
    }

    func moveResourcesToHeap(
        from textures: [MTLTexture],
        use heap: MTLHeap
    ) throws -> [MTLTexture] {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw NSError(domain: "ShaderConnection", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create command buffer"])
        }
        guard let encoder = commandBuffer.makeBlitCommandEncoder() else {
            throw NSError(domain: "ShaderConnection", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to create blit command encoder"])
        }

        var output: [MTLTexture] = []
        for texture in textures {
            let textureDescriptor: MTLTextureDescriptor = newDescriptorFromTexture(texture, storageMode: .private)
            let heapTexture = heap.makeTexture(descriptor: textureDescriptor)!
            var region = MTLRegionMake2D(0, 0, texture.width, texture.height)
            for level in 0..<texture.mipmapLevelCount {
                let sliceCount = switch texture.textureType {
                case .type1DArray, .type2DArray, .typeCubeArray, .type2DMultisampleArray:
                    texture.arrayLength
                case .typeCube:
                    6 // Each cube face is treated as a slice
                default:
                    1 // For 2D textures, there's only one slice
                }
                for slice in 0..<sliceCount {
                    encoder.copy(
                        from: texture,
                        sourceSlice: slice,
                        sourceLevel: level,
                        sourceOrigin: region.origin,
                        sourceSize: region.size,
                        to: heapTexture,
                        destinationSlice: slice,
                        destinationLevel: level,
                        destinationOrigin: region.origin
                    )
                }
                region.size.width /= 2
                region.size.height /= 2
                if region.size.width == 0 { region.size.width = 1 }
                if region.size.height == 0 { region.size.height = 1 }
            }
            output.append(heapTexture)
        }

        encoder.endEncoding()
        commandBuffer.commit()
        return output
    }

    func moveResourcesToHeap(
        from buffer: MTLBuffer,
        use heap: MTLHeap
    ) async throws -> MTLBuffer {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw NSError(domain: "ShaderConnection", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create command buffer"])
        }
        guard let encoder = commandBuffer.makeBlitCommandEncoder() else {
            throw NSError(domain: "ShaderConnection", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to create blit command encoder"])
        }

        let heapBuffer = heap.makeBuffer(
            length: buffer.length,
            options: [.storageModePrivate]
        )!
        encoder.copy(from: buffer, sourceOffset: 0, to: heapBuffer, destinationOffset: 0, size: buffer.length)

        encoder.endEncoding()
        await withCheckedContinuation { continuation in
            commandBuffer.addCompletedHandler { _ in continuation.resume() }
            commandBuffer.commit()
        }
        return heapBuffer
    }
}

