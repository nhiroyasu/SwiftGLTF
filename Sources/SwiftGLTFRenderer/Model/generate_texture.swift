import MetalKit

func generateEnvMap(commandQueue: MTLCommandQueue, faceFiles: [String]) -> MTLTexture {
    let device = commandQueue.device
    let textureLoader = MTKTextureLoader(device: device)

    var textures: [MTLTexture] = []
    for face in faceFiles {
        if let url = Bundle.main.url(forResource: face, withExtension: nil) {
            let texture = try! textureLoader.newTexture(
                URL: url,
                options: [
                    MTKTextureLoader.Option.textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
                    MTKTextureLoader.Option.textureStorageMode: NSNumber(value: MTLStorageMode.shared.rawValue)
                ]
            )
            textures.append(texture)
        }
    }

    let textureDescriptor = MTLTextureDescriptor.textureCubeDescriptor(
        pixelFormat: textures.first!.pixelFormat,
        size: textures.first!.width,
        mipmapped: true
    )
    textureDescriptor.usage = [.shaderRead]
    textureDescriptor.storageMode = .shared
    let envMap = device.makeTexture(descriptor: textureDescriptor)!

    // 各面にコピー
    for (index, texture) in textures.enumerated() {
        let region = MTLRegionMake2D(0, 0, texture.width, texture.height)
        let bytesPerRow = texture.width * 4 * MemoryLayout<Float16>.size
        let bytesPerImage = bytesPerRow * texture.height
        var imageData = [Float16](repeating: 0, count: texture.width * texture.height * 4)
        texture.getBytes(&imageData, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
        envMap.replace(
            region: region,
            mipmapLevel: 0,
            slice: index,
            withBytes: &imageData,
            bytesPerRow: bytesPerRow,
            bytesPerImage: bytesPerImage
        )
    }

    let commandBuffer = commandQueue.makeCommandBuffer()!
    let commandEncoder = commandBuffer.makeBlitCommandEncoder()!
    commandEncoder.generateMipmaps(for: envMap)
    commandEncoder.endEncoding()
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()

    return envMap
}

func generateEnvMap(commandQueue: MTLCommandQueue, color: simd_float3, size: Int = 128) -> MTLTexture {
    let device = commandQueue.device
    let textureDescriptor = MTLTextureDescriptor.textureCubeDescriptor(
        pixelFormat: .rgba16Float,
        size: size,
        mipmapped: true
    )
    textureDescriptor.usage = [.shaderRead, .shaderWrite]
    textureDescriptor.storageMode = .shared
    let envMap = device.makeTexture(descriptor: textureDescriptor)!

    let commandBuffer = commandQueue.makeCommandBuffer()!
    let commandEncoder = commandBuffer.makeBlitCommandEncoder()!

    for face in 0..<6 {
        let region = MTLRegionMake2D(0, 0, size, size)
        var colorData = [Float16](repeating: Float16(color.x), count: size * size * 4)
        for i in 1..<size * size {
            colorData[i * 4 + 1] = Float16(color.y)
            colorData[i * 4 + 2] = Float16(color.z)
            colorData[i * 4 + 3] = Float16(1.0)
        }
        envMap.replace(
            region: region,
            mipmapLevel: 0,
            slice: face,
            withBytes: &colorData,
            bytesPerRow: size * 4 * MemoryLayout<Float16>.size,
            bytesPerImage: size * size * 4 * MemoryLayout<Float16>.size
        )
    }

    commandEncoder.generateMipmaps(for: envMap)
    commandEncoder.endEncoding()
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()

    return envMap
}

func generateIrradianceTexture(
    commandQueue: MTLCommandQueue,
    library: MTLLibrary,
    envMap: MTLTexture,
    size: Int
) -> MTLTexture {
    let device = commandQueue.device
    let irradianceTextureDescriptor = MTLTextureDescriptor.textureCubeDescriptor(
        pixelFormat: envMap.pixelFormat,
        size: size,
        mipmapped: false
    )
    irradianceTextureDescriptor.usage = [.shaderRead, .shaderWrite]
    irradianceTextureDescriptor.storageMode = .shared
    let irradianceMap = device.makeTexture(descriptor: irradianceTextureDescriptor)!

    let irradianceKernel = library.makeFunction(name: "prefilterLambertEnvMap")!
    let irradiancePSO = try! device.makeComputePipelineState(function: irradianceKernel)
    let irradianceCommandBuffer = commandQueue.makeCommandBuffer()!
    let irradianceComputeEncoder = irradianceCommandBuffer.makeComputeCommandEncoder()!
    irradianceComputeEncoder.setComputePipelineState(irradiancePSO)
    irradianceComputeEncoder.setTexture(envMap, index: 0)
    irradianceComputeEncoder.setTexture(irradianceMap, index: 1)
    let threadsPerThreadgroupForPrefilter = MTLSize(width: 16, height: 16, depth: 1)
    let threadgroupsForPrefilter = MTLSize(
        width: irradianceMap.width / threadsPerThreadgroupForPrefilter.width,
        height: irradianceMap.height / threadsPerThreadgroupForPrefilter.height,
        depth: 6
    )
    irradianceComputeEncoder.dispatchThreadgroups(threadgroupsForPrefilter, threadsPerThreadgroup: threadsPerThreadgroupForPrefilter)
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
