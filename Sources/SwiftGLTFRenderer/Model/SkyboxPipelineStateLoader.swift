import MetalKit
import SwiftGLTFCore
import SwiftGLTFShaderTypes

public class SkyboxPipelineConnector {
    private let device: MTLDevice
    private let vertexFunction: MTLFunction
    private let fragmentFunction: MTLFunction
    let pso: MTLRenderPipelineState
    let dso: MTLDepthStencilState

    init(
        device: MTLDevice,
        library: MTLLibrary,
        config: SkyboxPipelineConfig
    ) throws {
        self.device = device
        self.vertexFunction = library.makeFunction(name: "skybox_vertex_shader")!
        self.fragmentFunction = library.makeFunction(name: "skybox_fragment_shader")!

        // Pipeline state
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = self.vertexFunction
        desc.fragmentFunction = self.fragmentFunction
        desc.colorAttachments[0].pixelFormat = config.colorPixelFormat
        desc.depthAttachmentPixelFormat = config.depthPixelFormat
        desc.rasterSampleCount = config.sampleCount
        desc.supportIndirectCommandBuffers = true
        self.pso = try device.makeRenderPipelineState(descriptor: desc)

        // Depth stencil state
        let dsd = MTLDepthStencilDescriptor()
        dsd.depthCompareFunction = .always
        dsd.isDepthWriteEnabled = false
        self.dso = device.makeDepthStencilState(descriptor: dsd)!
    }
}
