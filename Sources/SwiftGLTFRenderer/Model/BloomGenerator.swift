import Metal
import SwiftGLTFCore

private struct BloomExtractParams {
    let width: UInt32
    let height: UInt32
    let threshold: Float
    let padding: Float
}

class BloomGenerator {
    private let extractPSO: MTLComputePipelineState
    private let horizontalBlurPSO: MTLComputePipelineState
    private let verticalBlurPSO: MTLComputePipelineState

    init(device: MTLDevice) throws {
        let library = try device.makePackageLibrary()

        guard let extractKernel = library.makeFunction(name: "bloom_extract"),
              let horizontalBlurKernel = library.makeFunction(name: "bloom_blur_horizontal"),
              let verticalBlurKernel = library.makeFunction(name: "bloom_blur_vertical") else {
            throw SwiftGLTFRendererError(description: "Failed to find bloom kernel function")
        }

        extractPSO = try device.makeComputePipelineState(function: extractKernel)
        horizontalBlurPSO = try device.makeComputePipelineState(function: horizontalBlurKernel)
        verticalBlurPSO = try device.makeComputePipelineState(function: verticalBlurKernel)
    }

    func generate(
        from source: MTLTexture,
        extractTexture: MTLTexture,
        blurTexture: MTLTexture,
        bloomTexture: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) {
        guard let enc = commandBuffer.makeComputeCommandEncoder() else {
            return
        }

        let threadgroupSize = MTLSize(width: 8, height: 8, depth: 1)
        let threadgroupCount = MTLSize(
            width: (extractTexture.width + threadgroupSize.width - 1) / threadgroupSize.width,
            height: (extractTexture.height + threadgroupSize.height - 1) / threadgroupSize.height,
            depth: 1
        )
        var params = BloomExtractParams(
            width: UInt32(extractTexture.width),
            height: UInt32(extractTexture.height),
            threshold: 1.0,
            padding: 0.0
        )

        enc.label = "[SwiftGLTF] Bloom Compute Encoder"
        enc.setComputePipelineState(extractPSO)
        enc.setTexture(source, index: 0)
        enc.setTexture(extractTexture, index: 1)
        enc.setBytes(&params, length: MemoryLayout<BloomExtractParams>.size, index: 0)
        enc.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)

        enc.setComputePipelineState(horizontalBlurPSO)
        enc.setTexture(extractTexture, index: 0)
        enc.setTexture(blurTexture, index: 1)
        enc.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)

        enc.setComputePipelineState(verticalBlurPSO)
        enc.setTexture(blurTexture, index: 0)
        enc.setTexture(bloomTexture, index: 1)
        enc.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)

        enc.setComputePipelineState(horizontalBlurPSO)
        enc.setTexture(bloomTexture, index: 0)
        enc.setTexture(blurTexture, index: 1)
        enc.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)

        enc.setComputePipelineState(verticalBlurPSO)
        enc.setTexture(blurTexture, index: 0)
        enc.setTexture(bloomTexture, index: 1)
        enc.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)
        enc.endEncoding()
    }
}
