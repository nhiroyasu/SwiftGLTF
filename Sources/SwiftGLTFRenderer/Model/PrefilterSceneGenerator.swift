import Metal
import SwiftGLTFShaderTypes
import SwiftGLTFCore

class PrefilterSceneGenerator {
    private let device: MTLDevice
    private let library: MTLLibrary
    private let prefilterPSO: MTLComputePipelineState

    init(device: MTLDevice) throws {
        self.device = device
        self.library = try device.makePackageLibrary()

        guard let kernel = library.makeFunction(name: "prefilterScene2D") else {
            throw SwiftGLTFError.render(description: "Failed to find prefilterScene2D kernel function")
        }
        prefilterPSO = try device.makeComputePipelineState(function: kernel)
    }

    // Generate a prefiltered 2D texture pyramid from a base color buffer for rough transmission sampling
    func generate(
        from base: MTLTexture,
        to dst: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) {
        // Copy base level into mip 0 on the provided command buffer
        if let blit = commandBuffer.makeBlitCommandEncoder() {
            let region = MTLRegionMake2D(0, 0, base.width, base.height)
            blit.copy(from: base,
                      sourceSlice: 0,
                      sourceLevel: 0,
                      sourceOrigin: region.origin,
                      sourceSize: region.size,
                      to: dst,
                      destinationSlice: 0,
                      destinationLevel: 0,
                      destinationOrigin: region.origin)
            blit.endEncoding()
        }

        // Build mips 1..N with compute on the same command buffer
        if let enc = commandBuffer.makeComputeCommandEncoder() {
            enc.setComputePipelineState(prefilterPSO)
            enc.setTexture(dst, index: 0) // read prev level
            enc.setTexture(dst, index: 1) // write current level

            let mipCount = dst.mipmapLevelCount
            var w = dst.width
            var h = dst.height
            for level in 1..<mipCount {
                w = max(w >> 1, 1)
                h = max(h >> 1, 1)
                var params = Prefilter2DParams(width: UInt32(w), height: UInt32(h), mipLevel: UInt32(level))
                enc.setBytes(&params, length: MemoryLayout<Prefilter2DParams>.size, index: 0)
                let tg = MTLSize(width: 8, height: 8, depth: 1)
                let tgCount = MTLSize(width: (w + tg.width - 1) / tg.width,
                                      height: (h + tg.height - 1) / tg.height,
                                      depth: 1)
                enc.dispatchThreadgroups(tgCount, threadsPerThreadgroup: tg)
            }
            enc.endEncoding()
        }
    }
}
