import MetalKit
import SwiftGLTFShaderTypes
import SwiftGLTFCore

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
            throw SwiftGLTFError.makeRender(.convertShaderCreationFailed, context: .capture(stage: .render))
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
                throw SwiftGLTFError.makeRender(.outputTextureCreateFailed, context: .capture(stage: .render))
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
        commandBuffer.waitUntilCompleted()
        return output
    }

    func moveResourceToHeap(
        from texture: MTLTexture,
        use heap: MTLHeap
    ) throws -> MTLTexture {
        let results = try moveResourcesToHeap(from: [texture], use: heap)
        guard let firstTexture = results.first else {
            throw SwiftGLTFError.makeRender(.moveTextureToHeapFailed, context: .capture(stage: .render))
        }
        return firstTexture
    }

    func moveResourcesToHeap(
        from textures: [MTLTexture],
        use heap: MTLHeap
    ) throws -> [MTLTexture] {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw SwiftGLTFError.makeRender(.commandBufferCreateFailed, context: .capture(stage: .render))
        }
        guard let encoder = commandBuffer.makeBlitCommandEncoder() else {
            throw SwiftGLTFError.makeRender(.blitCommandEncoderCreateFailed, context: .capture(stage: .render))
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

    func moveBuffersToHeap(
        from buffers: [MTLBuffer],
        use heap: MTLHeap
    ) throws -> [MTLBuffer] {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw SwiftGLTFError.makeRender(.commandBufferCreateFailed, context: .capture(stage: .render))
        }
        guard let encoder = commandBuffer.makeBlitCommandEncoder() else {
            throw SwiftGLTFError.makeRender(.blitCommandEncoderCreateFailed, context: .capture(stage: .render))
        }

        var heapBuffers: [MTLBuffer] = []

        for sourceBuffer in buffers {
            guard let heapBuffer = heap.makeBuffer(
                length: sourceBuffer.length,
                options: [.storageModePrivate]
            ) else {
                throw SwiftGLTFError.makeRender(.heapBufferCreateFailed, context: .capture(stage: .render))
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

    func moveBufferToHeap(
        from buffer: MTLBuffer,
        use heap: MTLHeap
    ) throws -> MTLBuffer {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw SwiftGLTFError.makeRender(.commandBufferCreateFailed, context: .capture(stage: .render))
        }
        guard let encoder = commandBuffer.makeBlitCommandEncoder() else {
            throw SwiftGLTFError.makeRender(.blitCommandEncoderCreateFailed, context: .capture(stage: .render))
        }

        let heapBuffer = heap.makeBuffer(
            length: buffer.length,
            options: [.storageModePrivate]
        )!
        encoder.copy(from: buffer, sourceOffset: 0, to: heapBuffer, destinationOffset: 0, size: buffer.length)

        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return heapBuffer
    }


    func generatePrefilterEnvMapTexture(envMap: MTLTexture) -> MTLTexture {
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

    func generateBRDFLUT(width: Int, height: Int) -> MTLTexture {
        let brdfLUTTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rg16Float,
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
}
