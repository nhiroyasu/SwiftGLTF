import MetalKit
import SwiftGLTFShaderTypes
import SwiftGLTFCore

public class ShaderConnection {
    let device: MTLDevice
    let library: MTLLibrary
    let commandQueue: MTLCommandQueue

    public init(commandQueue: MTLCommandQueue) throws {
        self.device = commandQueue.device
        self.commandQueue = commandQueue
        self.library = try device.makePackageLibrary()
    }

    func computeBoundingSpheres(meshes: [PBRMesh]) throws -> MTLBuffer {
        let count = meshes.count
        let outBuffer = device.makeBuffer(
            length: MemoryLayout<SIMD4<Float>>.stride * max(count, 1),
            options: .storageModeShared
        )!

        guard count > 0 else { return outBuffer }

        guard let function = library.makeFunction(name: "computeBoundingSphereForMesh") else {
            throw SwiftGLTFRendererError(description: "Failed to create convert shader")
        }
        let pso = try device.makeComputePipelineState(function: function)

        let cb = commandQueue.makeCommandBuffer()!
        let encoder = cb.makeComputeCommandEncoder()!
        encoder.setComputePipelineState(pso)

        let threadsPerThreadgroup = MTLSize(width: 256, height: 1, depth: 1)
        for (i, mesh) in meshes.enumerated() {
            var vtxCount = UInt32(mesh.vertexCount)
            var stride = UInt32(mesh.positionStride)
            var offset = UInt32(mesh.positionOffset)
            var outIndex = UInt32(i)

            encoder.setBuffer(mesh.vertexBuffer, offset: 0, index: 0)
            encoder.setBytes(&vtxCount, length: MemoryLayout<UInt32>.size, index: 1)
            encoder.setBytes(&stride, length: MemoryLayout<UInt32>.size, index: 2)
            encoder.setBytes(&offset, length: MemoryLayout<UInt32>.size, index: 3)
            encoder.setBuffer(outBuffer, offset: 0, index: 4)
            encoder.setBytes(&outIndex, length: MemoryLayout<UInt32>.size, index: 5)

            let groups = MTLSize(width: 1, height: 1, depth: 1)
            encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: threadsPerThreadgroup)
        }

        encoder.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()

        return outBuffer
    }

    func encodeComputeBoundingSpheres(_ commandBuffer: MTLCommandBuffer, meshes: [PBRMesh]) throws -> MTLBuffer {
        let count = meshes.count
        let outBuffer = device.makeBuffer(
            length: MemoryLayout<SIMD4<Float>>.stride * max(count, 1),
            options: .storageModeShared
        )!

        guard count > 0 else { return outBuffer }

        guard let function = library.makeFunction(name: "computeBoundingSphereForMesh") else {
            throw SwiftGLTFRendererError(description: "Failed to create convert shader")
        }
        let pso = try device.makeComputePipelineState(function: function)

        let encoder = commandBuffer.makeComputeCommandEncoder()!
        encoder.setComputePipelineState(pso)

        let threadsPerThreadgroup = MTLSize(width: 256, height: 1, depth: 1)
        for (i, mesh) in meshes.enumerated() {
            var vtxCount = UInt32(mesh.vertexCount)
            var stride = UInt32(mesh.positionStride)
            var offset = UInt32(mesh.positionOffset)
            var outIndex = UInt32(i)

            encoder.setBuffer(mesh.vertexBuffer, offset: 0, index: 0)
            encoder.setBytes(&vtxCount, length: MemoryLayout<UInt32>.size, index: 1)
            encoder.setBytes(&stride, length: MemoryLayout<UInt32>.size, index: 2)
            encoder.setBytes(&offset, length: MemoryLayout<UInt32>.size, index: 3)
            encoder.setBuffer(outBuffer, offset: 0, index: 4)
            encoder.setBytes(&outIndex, length: MemoryLayout<UInt32>.size, index: 5)

            let groups = MTLSize(width: 1, height: 1, depth: 1)
            encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: threadsPerThreadgroup)
        }

        encoder.endEncoding()
        return outBuffer
    }

    func convertSrgb2Linear(textures: [MTLTexture]) throws -> [MTLTexture] {
        let commandBuffer = commandQueue.makeCommandBuffer()!
        guard let convertShader = library.makeFunction(name: "texture_srgb_2_linear_shader") else {
            throw SwiftGLTFRendererError(description: "Failed to create convert shader")
        }
        let pso = try device.makeComputePipelineState(function: convertShader)

        var output: [MTLTexture] = []
        for texture in textures {
            let outputTextureDescriptor = MTLTextureDescriptor()
            outputTextureDescriptor.pixelFormat = .rgba32Float
            outputTextureDescriptor.width = texture.width
            outputTextureDescriptor.height = texture.height
            outputTextureDescriptor.mipmapLevelCount = texture.mipmapLevelCount
            outputTextureDescriptor.textureType = texture.textureType
            outputTextureDescriptor.arrayLength = texture.arrayLength
            outputTextureDescriptor.usage = [.shaderRead, .shaderWrite]
            guard let outputTexture = texture.device.makeTexture(descriptor: outputTextureDescriptor) else {
                throw SwiftGLTFRendererError(description: "Failed to create output texture")
            }

            let computeEncoder = commandBuffer.makeComputeCommandEncoder()!
            computeEncoder.setComputePipelineState(pso)

            // 各mipmapレベルに対して変換処理を実行
            for mipLevel in 0..<texture.mipmapLevelCount {
                let mipWidth = max(texture.width >> mipLevel, 1)
                let mipHeight = max(texture.height >> mipLevel, 1)

                // テクスチャビューを作成して特定のmipmapレベルを指定
                let inputTextureView = texture.makeTextureView(
                    pixelFormat: texture.pixelFormat,
                    textureType: texture.textureType,
                    levels: mipLevel..<(mipLevel + 1),
                    slices: 0..<texture.arrayLength
                )!

                let outputTextureView = outputTexture.makeTextureView(
                    pixelFormat: outputTexture.pixelFormat,
                    textureType: outputTexture.textureType,
                    levels: mipLevel..<(mipLevel + 1),
                    slices: 0..<outputTexture.arrayLength
                )!

                computeEncoder.setTexture(inputTextureView, index: 0)
                computeEncoder.setTexture(outputTextureView, index: 1)

                let threadsPerThreadgroup = MTLSize(width: 16, height: 16, depth: 1)
                let threadgroups = MTLSize(
                    width: (mipWidth + threadsPerThreadgroup.width - 1) / threadsPerThreadgroup.width,
                    height: (mipHeight + threadsPerThreadgroup.height - 1) / threadsPerThreadgroup.height,
                    depth: 1
                )
                computeEncoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
            }

            computeEncoder.endEncoding()
            output.append(outputTexture)
        }

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return output
    }

    func encodeConvertSrgb2Linear(_ commandBuffer: MTLCommandBuffer, textures: [MTLTexture]) throws -> [MTLTexture] {
        guard let convertShader = library.makeFunction(name: "texture_srgb_2_linear_shader") else {
            throw SwiftGLTFRendererError(description: "Failed to create convert shader")
        }
        let pso = try device.makeComputePipelineState(function: convertShader)

        var output: [MTLTexture] = []
        for texture in textures {
            let outputTextureDescriptor = MTLTextureDescriptor()
            outputTextureDescriptor.pixelFormat = .rgba32Float
            outputTextureDescriptor.width = texture.width
            outputTextureDescriptor.height = texture.height
            outputTextureDescriptor.mipmapLevelCount = texture.mipmapLevelCount
            outputTextureDescriptor.textureType = texture.textureType
            outputTextureDescriptor.arrayLength = texture.arrayLength
            outputTextureDescriptor.usage = [.shaderRead, .shaderWrite]
            guard let outputTexture = texture.device.makeTexture(descriptor: outputTextureDescriptor) else {
                throw SwiftGLTFRendererError(description: "Failed to create output texture")
            }

            let computeEncoder = commandBuffer.makeComputeCommandEncoder()!
            computeEncoder.setComputePipelineState(pso)

            // 各mipmapレベルに対して変換処理を実行
            for mipLevel in 0..<texture.mipmapLevelCount {
                let mipWidth = max(texture.width >> mipLevel, 1)
                let mipHeight = max(texture.height >> mipLevel, 1)

                // テクスチャビューを作成して特定のmipmapレベルを指定
                let inputTextureView = texture.makeTextureView(
                    pixelFormat: texture.pixelFormat,
                    textureType: texture.textureType,
                    levels: mipLevel..<(mipLevel + 1),
                    slices: 0..<texture.arrayLength
                )!

                let outputTextureView = outputTexture.makeTextureView(
                    pixelFormat: outputTexture.pixelFormat,
                    textureType: outputTexture.textureType,
                    levels: mipLevel..<(mipLevel + 1),
                    slices: 0..<outputTexture.arrayLength
                )!

                computeEncoder.setTexture(inputTextureView, index: 0)
                computeEncoder.setTexture(outputTextureView, index: 1)

                let threadsPerThreadgroup = MTLSize(width: 16, height: 16, depth: 1)
                let threadgroups = MTLSize(
                    width: (mipWidth + threadsPerThreadgroup.width - 1) / threadsPerThreadgroup.width,
                    height: (mipHeight + threadsPerThreadgroup.height - 1) / threadsPerThreadgroup.height,
                    depth: 1
                )
                computeEncoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
            }

            computeEncoder.endEncoding()
            output.append(outputTexture)
        }
        return output
    }

    func moveResourceToHeap(
        from texture: MTLTexture,
        use heap: MTLHeap
    ) throws -> MTLTexture {
        let results = try moveResourcesToHeap(from: [texture], use: heap)
        guard let firstTexture = results.first else {
            throw SwiftGLTFRendererError(description: "Failed to move texture to heap")
        }
        return firstTexture
    }

    func moveResourcesToHeap(
        from textures: [MTLTexture],
        use heap: MTLHeap
    ) throws -> [MTLTexture] {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw SwiftGLTFRendererError(description: "Failed to create command buffer")
        }
        guard let encoder = commandBuffer.makeBlitCommandEncoder() else {
            throw SwiftGLTFRendererError(description: "Failed to create blit command encoder")
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
        commandBuffer.waitUntilCompleted()
        return output
    }

    func encodeMoveResourcesToHeap(
        _ commandBuffer: MTLCommandBuffer,
        from textures: [MTLTexture],
        use heap: MTLHeap
    ) throws -> [MTLTexture] {
        guard let encoder = commandBuffer.makeBlitCommandEncoder() else {
            throw SwiftGLTFRendererError(description: "Failed to create blit command encoder")
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
        return output
    }

    func encodeTransportToHeap(
        _ commandBuffer: MTLCommandBuffer,
        from buffer: MTLBuffer,
        use heap: MTLHeap
    ) throws -> MTLBuffer {
        guard let encoder = commandBuffer.makeBlitCommandEncoder() else {
            throw SwiftGLTFRendererError(description: "Failed to create blit command encoder")
        }

        let heapBuffer = heap.makeBuffer(
            length: buffer.length,
            options: [.storageModePrivate]
        )
        guard let heapBuffer else {
            throw SwiftGLTFRendererError(description: "Failed to create heap buffer")
        }

        encoder.copy(from: buffer, sourceOffset: 0, to: heapBuffer, destinationOffset: 0, size: buffer.length)

        encoder.endEncoding()
        return heapBuffer
    }

    func moveBuffersToHeap(
        from buffers: [MTLBuffer],
        use heap: MTLHeap
    ) throws -> [MTLBuffer] {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw SwiftGLTFRendererError(description: "Failed to create command buffer")
        }
        guard let encoder = commandBuffer.makeBlitCommandEncoder() else {
            throw SwiftGLTFRendererError(description: "Failed to create blit command encoder")
        }

        var heapBuffers: [MTLBuffer] = []

        for sourceBuffer in buffers {
            guard let heapBuffer = heap.makeBuffer(
                length: sourceBuffer.length,
                options: [.storageModePrivate]
            ) else {
                throw SwiftGLTFRendererError(description: "Failed to create heap buffer")
            }
            encoder.copy(
                from: sourceBuffer,
                sourceOffset: 0,
                to: heapBuffer,
                destinationOffset: 0,
                size: sourceBuffer.length
            )
            heapBuffers.append(heapBuffer)
        }

        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return heapBuffers
    }

    func encodeMoveBuffersToHeap(
        _ commandBuffer: MTLCommandBuffer,
        from buffers: [MTLBuffer],
        use heap: MTLHeap
    ) throws -> [MTLBuffer] {
        guard let encoder = commandBuffer.makeBlitCommandEncoder() else {
            throw SwiftGLTFRendererError(description: "Failed to create blit command encoder")
        }

        var heapBuffers: [MTLBuffer] = []

        for sourceBuffer in buffers {
            guard let heapBuffer = heap.makeBuffer(
                length: sourceBuffer.length,
                options: [.storageModePrivate]
            ) else {
                throw SwiftGLTFRendererError(description: "Failed to create heap buffer")
            }
            encoder.copy(
                from: sourceBuffer,
                sourceOffset: 0,
                to: heapBuffer,
                destinationOffset: 0,
                size: sourceBuffer.length
            )
            heapBuffers.append(heapBuffer)
        }

        encoder.endEncoding()
        return heapBuffers
    }

    func moveBufferToHeap(
        from buffer: MTLBuffer,
        use heap: MTLHeap
    ) throws -> MTLBuffer {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw SwiftGLTFRendererError(description: "Failed to create command buffer")
        }
        guard let encoder = commandBuffer.makeBlitCommandEncoder() else {
            throw SwiftGLTFRendererError(description: "Failed to create blit command encoder")
        }

        let heapBuffer = heap.makeBuffer(
            length: buffer.length,
            options: [.storageModePrivate]
        )
        guard let heapBuffer else {
            throw SwiftGLTFRendererError(description: "Failed to create heap buffer")
        }

        encoder.copy(from: buffer, sourceOffset: 0, to: heapBuffer, destinationOffset: 0, size: buffer.length)

        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return heapBuffer
    }

    func encodeMoveBufferToHeap(
        _ commandBuffer: MTLCommandBuffer,
        from buffer: MTLBuffer,
        use heap: MTLHeap
    ) throws -> MTLBuffer {
        guard let encoder = commandBuffer.makeBlitCommandEncoder() else {
            throw SwiftGLTFRendererError(description: "Failed to create blit command encoder")
        }

        let heapBuffer = heap.makeBuffer(
            length: buffer.length,
            options: [.storageModePrivate]
        )
        guard let heapBuffer else {
            throw SwiftGLTFRendererError(description: "Failed to create heap buffer")
        }

        encoder.copy(from: buffer, sourceOffset: 0, to: heapBuffer, destinationOffset: 0, size: buffer.length)

        encoder.endEncoding()
        return heapBuffer
    }

    func copyValueToBuffer<T>(valuePtr: UnsafePointer<T>, dst: MTLBuffer) throws {
        let length = MemoryLayout<T>.size
        let staging = device.makeBuffer(bytes: valuePtr, length: length, options: .storageModeShared)!
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw SwiftGLTFRendererError(description: "Failed to create command buffer")
        }
        guard let encoder = commandBuffer.makeBlitCommandEncoder() else {
            throw SwiftGLTFRendererError(description: "Failed to create blit command encoder")
        }
        encoder.copy(from: staging, sourceOffset: 0, to: dst, destinationOffset: 0, size: length)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    func generatePrefilterEnvMapTexture(envMap: MTLTexture) -> MTLTexture {
        guard envMap.mipmapLevelCount > 1 else {
            fatalError("Environment map must have mipmaps for prefiltering.")
        }
        let prefilterEnvMapKernel = library.makeFunction(name: "prefilterEnvMap")!
        let pso = try! device.makeComputePipelineState(function: prefilterEnvMapKernel)
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
        commandEncoder.setComputePipelineState(pso)

        let prefilterEnvMapDescriptor = MTLTextureDescriptor.textureCubeDescriptor(
            pixelFormat: .rgba16Float,
            size: envMap.width,
            mipmapped: true
        )
        prefilterEnvMapDescriptor.usage = [.shaderRead, .shaderWrite]
        prefilterEnvMapDescriptor.storageMode = .shared
        let prefilterEnvMap = device.makeTexture(descriptor: prefilterEnvMapDescriptor)!

        commandEncoder.setTexture(envMap, index: 0)
        commandEncoder.setTexture(prefilterEnvMap, index: 1)

        let mipCount = envMap.mipmapLevelCount
        let textureSize = envMap.width
        for mipLevel in 0..<mipCount {
            let roughness = Float(mipLevel) / Float(mipCount - 1)
            let cubeSize = max(textureSize >> mipLevel, 1)

            var params = PreFilterEnvMapParams(
                roughness: roughness,
                mipLevel: UInt32(mipLevel),
                cubeSize: UInt32(cubeSize),
                sampleCount: 1024
            )
            commandEncoder.setBytes(&params, length: MemoryLayout<PreFilterEnvMapParams>.size, index: 0)
            let threads = MTLSize(width: 16, height: 16, depth: 1)
            let threadGroups = MTLSize(
                width: (cubeSize + threads.width - 1) / threads.width,
                height: (cubeSize + threads.height - 1) / threads.height,
                depth: 6
            )
            commandEncoder.dispatchThreadgroups(
                threadGroups,
                threadsPerThreadgroup: threads
            )
        }
        commandEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return prefilterEnvMap
    }

    func encodePrefilterEnvMapTexture(
        _ commandBuffer: MTLCommandBuffer,
        envMap: MTLTexture,
        waitFence: MTLFence? = nil
    ) throws -> MTLTexture {
        guard envMap.mipmapLevelCount > 1 else {
            throw SwiftGLTFRendererError(description: "Environment map must have mipmaps for prefiltering.")
        }
        let prefilterEnvMapKernel = library.makeFunction(name: "prefilterEnvMap")!
        let pso = try device.makeComputePipelineState(function: prefilterEnvMapKernel)
        let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
        if let waitFence {
            commandEncoder.waitForFence(waitFence)
        }
        commandEncoder.setComputePipelineState(pso)

        let prefilterEnvMapDescriptor = MTLTextureDescriptor.textureCubeDescriptor(
            pixelFormat: .rgba16Float,
            size: envMap.width,
            mipmapped: true
        )
        prefilterEnvMapDescriptor.usage = [.shaderRead, .shaderWrite]
        prefilterEnvMapDescriptor.storageMode = .shared
        let prefilterEnvMap = device.makeTexture(descriptor: prefilterEnvMapDescriptor)!

        commandEncoder.setTexture(envMap, index: 0)
        commandEncoder.setTexture(prefilterEnvMap, index: 1)

        let mipCount = envMap.mipmapLevelCount
        let textureSize = envMap.width
        for mipLevel in 0..<mipCount {
            let roughness = Float(mipLevel) / Float(mipCount - 1)
            let cubeSize = max(textureSize >> mipLevel, 1)

            var params = PreFilterEnvMapParams(
                roughness: roughness,
                mipLevel: UInt32(mipLevel),
                cubeSize: UInt32(cubeSize),
                sampleCount: 1024
            )
            commandEncoder.setBytes(&params, length: MemoryLayout<PreFilterEnvMapParams>.size, index: 0)
            let threads = MTLSize(width: 16, height: 16, depth: 1)
            let threadGroups = MTLSize(
                width: (cubeSize + threads.width - 1) / threads.width,
                height: (cubeSize + threads.height - 1) / threads.height,
                depth: 6
            )
            commandEncoder.dispatchThreadgroups(
                threadGroups,
                threadsPerThreadgroup: threads
            )
        }
        commandEncoder.endEncoding()
        return prefilterEnvMap
    }

    func generateIrradianceTexture(envMap: MTLTexture, size: Int) -> MTLTexture {
        let irradianceKernel = library.makeFunction(name: "irradianceMap")!
        let irradiancePSO = try! device.makeComputePipelineState(function: irradianceKernel)
        let irradianceCommandBuffer = commandQueue.makeCommandBuffer()!
        let irradianceComputeEncoder = irradianceCommandBuffer.makeComputeCommandEncoder()!
        irradianceComputeEncoder.setComputePipelineState(irradiancePSO)

        let irradianceTextureDescriptor = MTLTextureDescriptor.textureCubeDescriptor(
            pixelFormat: .rgba16Float,
            size: size,
            mipmapped: false
        )
        irradianceTextureDescriptor.usage = [.shaderRead, .shaderWrite]
        irradianceTextureDescriptor.storageMode = .shared
        let irradianceMap = device.makeTexture(descriptor: irradianceTextureDescriptor)!
        irradianceComputeEncoder.setTexture(envMap, index: 0)
        irradianceComputeEncoder.setTexture(irradianceMap, index: 1)

        var params = IrradianceMapParams(
            cubeSize: UInt32(size)
        )
        irradianceComputeEncoder.setBytes(&params, length: MemoryLayout<IrradianceMapParams>.size, index: 0)

        let threads = MTLSize(width: 16, height: 16, depth: 1)
        let threadGroups = MTLSize(
            width: (size + threads.width - 1) / threads.width,
            height: (size + threads.height - 1) / threads.height,
            depth: 6
        )
        irradianceComputeEncoder.dispatchThreadgroups(
            threadGroups,
            threadsPerThreadgroup: threads
        )
        irradianceComputeEncoder.endEncoding()
        irradianceCommandBuffer.commit()
        irradianceCommandBuffer.waitUntilCompleted()
        return irradianceMap
    }

    func encodeIrradianceTexture(
        _ commandBuffer: MTLCommandBuffer,
        envMap: MTLTexture,
        size: Int,
        waitFence: MTLFence? = nil
    ) throws -> MTLTexture {
        let irradianceKernel = library.makeFunction(name: "irradianceMap")!
        let irradiancePSO = try device.makeComputePipelineState(function: irradianceKernel)
        let irradianceComputeEncoder = commandBuffer.makeComputeCommandEncoder()!
        if let waitFence {
            irradianceComputeEncoder.waitForFence(waitFence)
        }
        irradianceComputeEncoder.setComputePipelineState(irradiancePSO)

        let irradianceTextureDescriptor = MTLTextureDescriptor.textureCubeDescriptor(
            pixelFormat: .rgba16Float,
            size: size,
            mipmapped: false
        )
        irradianceTextureDescriptor.usage = [.shaderRead, .shaderWrite]
        irradianceTextureDescriptor.storageMode = .shared
        let irradianceMap = device.makeTexture(descriptor: irradianceTextureDescriptor)!
        irradianceComputeEncoder.setTexture(envMap, index: 0)
        irradianceComputeEncoder.setTexture(irradianceMap, index: 1)

        var params = IrradianceMapParams(
            cubeSize: UInt32(size)
        )
        irradianceComputeEncoder.setBytes(&params, length: MemoryLayout<IrradianceMapParams>.size, index: 0)

        let threads = MTLSize(width: 16, height: 16, depth: 1)
        let threadGroups = MTLSize(
            width: (size + threads.width - 1) / threads.width,
            height: (size + threads.height - 1) / threads.height,
            depth: 6
        )
        irradianceComputeEncoder.dispatchThreadgroups(
            threadGroups,
            threadsPerThreadgroup: threads
        )
        irradianceComputeEncoder.endEncoding()
        return irradianceMap
    }

    func generateBRDFLUT(width: Int, height: Int) -> MTLTexture {
        let brdfLUTTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: width,
            height: height,
            mipmapped: false
        )
        brdfLUTTextureDescriptor.usage = [.shaderRead, .shaderWrite]
        brdfLUTTextureDescriptor.storageMode = .shared
        let lut = device.makeTexture(descriptor: brdfLUTTextureDescriptor)!

        let brdfKernel = library.makeFunction(name: "generateBRDFLUT")!
        let brdfPSO = try! device.makeComputePipelineState(function: brdfKernel)

        let brdfCommandBuffer = commandQueue.makeCommandBuffer()!
        let brdfComputeEncoder = brdfCommandBuffer.makeComputeCommandEncoder()!
        brdfComputeEncoder.setComputePipelineState(brdfPSO)
        brdfComputeEncoder.setTexture(lut, index: 0)

        let threadsPerThreadgroup = MTLSize(width: 16, height: 16, depth: 1)
        let threadgroups = MTLSize(
            width: lut.width + (threadsPerThreadgroup.width - 1) / threadsPerThreadgroup.width,
            height: lut.height + (threadsPerThreadgroup.height - 1) / threadsPerThreadgroup.height,
            depth: 1
        )
        brdfComputeEncoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)

        brdfComputeEncoder.endEncoding()
        brdfCommandBuffer.commit()
        brdfCommandBuffer.waitUntilCompleted()

        return lut
    }

    func encodeBRDFLUT(
        _ commandBuffer: MTLCommandBuffer,
        width: Int,
        height: Int
    ) throws -> MTLTexture {
        let brdfLUTTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: width,
            height: height,
            mipmapped: false
        )
        brdfLUTTextureDescriptor.usage = [.shaderRead, .shaderWrite]
        brdfLUTTextureDescriptor.storageMode = .shared
        let lut = device.makeTexture(descriptor: brdfLUTTextureDescriptor)!

        let brdfKernel = library.makeFunction(name: "generateBRDFLUT")!
        let brdfPSO = try device.makeComputePipelineState(function: brdfKernel)

        let brdfComputeEncoder = commandBuffer.makeComputeCommandEncoder()!
        brdfComputeEncoder.setComputePipelineState(brdfPSO)
        brdfComputeEncoder.setTexture(lut, index: 0)

        let threadsPerThreadgroup = MTLSize(width: 16, height: 16, depth: 1)
        let threadgroups = MTLSize(
            width: lut.width + (threadsPerThreadgroup.width - 1) / threadsPerThreadgroup.width,
            height: lut.height + (threadsPerThreadgroup.height - 1) / threadsPerThreadgroup.height,
            depth: 1
        )
        brdfComputeEncoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)

        brdfComputeEncoder.endEncoding()
        return lut
    }

    func generatePrefilterSheenTexture(envMap: MTLTexture) -> MTLTexture {
        guard envMap.mipmapLevelCount > 1 else {
            fatalError("Environment map must have mipmaps for prefiltering.")
        }
        let prefilterSheenKernel = library.makeFunction(name: "prefilterSheenEnvMap")!
        let pso = try! device.makeComputePipelineState(function: prefilterSheenKernel)
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
        commandEncoder.setComputePipelineState(pso)

        let prefilterSheenDescriptor = MTLTextureDescriptor.textureCubeDescriptor(
            pixelFormat: .rgba16Float,
            size: envMap.width,
            mipmapped: true
        )
        prefilterSheenDescriptor.usage = [.shaderRead, .shaderWrite]
        prefilterSheenDescriptor.storageMode = .shared
        let sheenTex = device.makeTexture(descriptor: prefilterSheenDescriptor)!

        commandEncoder.setTexture(envMap, index: 0)
        commandEncoder.setTexture(sheenTex, index: 1)

        let mipCount = envMap.mipmapLevelCount
        let textureSize = envMap.width
        for mipLevel in 0..<mipCount {
            let roughness = Float(mipLevel) / Float(mipCount - 1)
            let cubeSize = max(textureSize >> mipLevel, 1)

            var params = PreFilterSheenEnvMapParams(
                roughness: roughness,
                mipLevel: UInt32(mipLevel),
                cubeSize: UInt32(cubeSize),
                sampleCount: 2048
            )
            commandEncoder.setBytes(&params, length: MemoryLayout<PreFilterSheenEnvMapParams>.size, index: 0)
            let threads = MTLSize(width: 16, height: 16, depth: 1)
            let threadGroups = MTLSize(
                width: (cubeSize + threads.width - 1) / threads.width,
                height: (cubeSize + threads.height - 1) / threads.height,
                depth: 6
            )
            commandEncoder.dispatchThreadgroups(
                threadGroups,
                threadsPerThreadgroup: threads
            )
        }
        commandEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return sheenTex
    }

    func encodePrefilterSheenTexture(
        _ commandBuffer: MTLCommandBuffer,
        envMap: MTLTexture,
        waitFence: MTLFence? = nil
    ) throws -> MTLTexture {
        guard envMap.mipmapLevelCount > 1 else {
            fatalError("Environment map must have mipmaps for prefiltering.")
        }
        let prefilterSheenKernel = library.makeFunction(name: "prefilterSheenEnvMap")!
        let pso = try device.makeComputePipelineState(function: prefilterSheenKernel)
        let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
        if let waitFence {
            commandEncoder.waitForFence(waitFence)
        }
        commandEncoder.setComputePipelineState(pso)

        let prefilterSheenDescriptor = MTLTextureDescriptor.textureCubeDescriptor(
            pixelFormat: .rgba16Float,
            size: envMap.width,
            mipmapped: true
        )
        prefilterSheenDescriptor.usage = [.shaderRead, .shaderWrite]
        prefilterSheenDescriptor.storageMode = .shared
        let sheenTex = device.makeTexture(descriptor: prefilterSheenDescriptor)!

        commandEncoder.setTexture(envMap, index: 0)
        commandEncoder.setTexture(sheenTex, index: 1)

        let mipCount = envMap.mipmapLevelCount
        let textureSize = envMap.width
        for mipLevel in 0..<mipCount {
            let roughness = Float(mipLevel) / Float(mipCount - 1)
            let cubeSize = max(textureSize >> mipLevel, 1)

            var params = PreFilterSheenEnvMapParams(
                roughness: roughness,
                mipLevel: UInt32(mipLevel),
                cubeSize: UInt32(cubeSize),
                sampleCount: 2048
            )
            commandEncoder.setBytes(&params, length: MemoryLayout<PreFilterSheenEnvMapParams>.size, index: 0)
            let threads = MTLSize(width: 16, height: 16, depth: 1)
            let threadGroups = MTLSize(
                width: (cubeSize + threads.width - 1) / threads.width,
                height: (cubeSize + threads.height - 1) / threads.height,
                depth: 6
            )
            commandEncoder.dispatchThreadgroups(
                threadGroups,
                threadsPerThreadgroup: threads
            )
        }
        commandEncoder.endEncoding()
        return sheenTex
    }

    func computeWorldMatrices(
        nodeLevelHierarchy nlh: NodeLevelHierarchy
    ) throws -> MTLBuffer {
        let cb = commandQueue.makeCommandBuffer()!
        let en = cb.makeComputeCommandEncoder()!

        let worldTransformBuf = device.makeBuffer(
            length: MemoryLayout<simd_float4x4>.stride * nlh.localTransforms.count,
            options: .storageModeShared
        )!

        try computeWorldMatrices(
            nodeLevelHierarchy: nlh,
            out: worldTransformBuf,
            commandEncoder: en
        )
        cb.commit()
        cb.waitUntilCompleted()
        return worldTransformBuf
    }

    func encodeComputeWorldMatrices(
        _ commandBuffer: MTLCommandBuffer,
        nodeLevelHierarchy nlh: NodeLevelHierarchy
    ) throws -> MTLBuffer {
        let en = commandBuffer.makeComputeCommandEncoder()!

        let worldTransformBuf = device.makeBuffer(
            length: MemoryLayout<simd_float4x4>.stride * nlh.localTransforms.count,
            options: .storageModeShared
        )!

        try computeWorldMatrices(
            nodeLevelHierarchy: nlh,
            out: worldTransformBuf,
            commandEncoder: en
        )
        return worldTransformBuf
    }

    func computeWorldMatrices(
        nodeLevelHierarchy nlh: NodeLevelHierarchy,
        out worldTransformBuf: MTLBuffer,
        commandEncoder en: MTLComputeCommandEncoder,
    ) throws {
        precondition(worldTransformBuf.length == MemoryLayout<simd_float4x4>.stride * nlh.localTransforms.count)

        let device = en.device
        let computePso = try device.makeComputePipelineState(function: library.makeFunction(name: "computeWorldMatrices")!)

        var levelDispatch: [LevelDispatch] = []
        for (start, count) in zip(nlh.levelStarts, nlh.levelCounts) {
            levelDispatch.append(
                LevelDispatch(
                    start: Int64(start),
                    count: Int64(count)
                )
            )
        }
        let levelNodesBuf = device.makeBuffer(
            bytes: nlh.levelNodes,
            length: MemoryLayout<Int>.stride * nlh.levelNodes.count,
            options: .storageModeShared
        )!
        let parentIndexBuf = device.makeBuffer(
            bytes: nlh.parentIndex,
            length: MemoryLayout<Int>.stride * nlh.parentIndex.count,
            options: .storageModeShared
        )!
        let localTransformBuf = device.makeBuffer(
            bytes: nlh.localTransforms,
            length: MemoryLayout<simd_float4x4>.stride * nlh.localTransforms.count,
            options: .storageModeShared
        )!
        for d in 0..<nlh.maxDepth {
            en.setComputePipelineState(computePso)

            en.setBytes(&levelDispatch[d], length: MemoryLayout<LevelDispatch>.size, index: 0)
            en.setBuffer(levelNodesBuf, offset: 0, index: 1)
            en.setBuffer(parentIndexBuf, offset: 0, index: 2)
            en.setBuffer(localTransformBuf, offset: 0, index: 3)
            en.setBuffer(worldTransformBuf, offset: 0, index: 4)
            let levelCount = nlh.levelCounts[d]
            let threadSize = min(computePso.maxTotalThreadsPerThreadgroup, levelCount)
            let threads = MTLSize(width: threadSize, height: 1, depth: 1)
            let groups = MTLSize(
                width: (levelCount+threads.width-1) / threads.width,
                height: 1,
                depth: 1
            )
            en.dispatchThreadgroups(groups, threadsPerThreadgroup: threads)
        }
        en.endEncoding()
    }
}
