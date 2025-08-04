import MetalKit
import SwiftGLTFShaderTypes

func generatePrefilterEnvMapTexture(
    commandQueue: MTLCommandQueue,
    library: MTLLibrary,
    envMap: MTLTexture
) -> MTLTexture {
    let device = commandQueue.device
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

func generateIrradianceTexture(
    commandQueue: MTLCommandQueue,
    library: MTLLibrary,
    envMap: MTLTexture,
    size: Int
) -> MTLTexture {
    let device = commandQueue.device
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

func generateBRDFLUT(commandQueue: MTLCommandQueue, library: MTLLibrary, width: Int, height: Int) -> MTLTexture {
    let device = commandQueue.device
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

func newDescriptorFromTexture(_ texture: MTLTexture, storageMode: MTLStorageMode) -> MTLTextureDescriptor {
    let descriptor = MTLTextureDescriptor()
    descriptor.textureType      = texture.textureType
    descriptor.pixelFormat      = texture.pixelFormat
    descriptor.width            = texture.width
    descriptor.height           = texture.height
    descriptor.depth            = texture.depth
    descriptor.mipmapLevelCount = texture.mipmapLevelCount
    descriptor.arrayLength      = texture.arrayLength
    descriptor.sampleCount      = texture.sampleCount
    descriptor.storageMode      = storageMode
    return descriptor
}
