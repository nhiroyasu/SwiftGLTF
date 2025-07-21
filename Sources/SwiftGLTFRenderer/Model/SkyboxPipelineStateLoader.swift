import MetalKit

public class SkyboxPipelineStateLoader {
    private let device: MTLDevice
    private let library: MTLLibrary
    private let config: PipelineStateLoaderConfig

    private var cachedPipelineState: MTLRenderPipelineState?

    public init(
        device: MTLDevice,
        library: MTLLibrary,
        config: PipelineStateLoaderConfig = PipelineStateLoaderConfig()
    ) {
        self.device = device
        self.library = library
        self.config = config
    }

    func load(
        for vertexDescriptor: MDLVertexDescriptor,
        useCache: Bool = true
    ) throws -> MTLRenderPipelineState {
        if useCache, let cached = cachedPipelineState {
            return cached
        }

        let desc = MTLRenderPipelineDescriptor()
        desc.label = "Skybox Pipeline"
        desc.vertexFunction = library.makeFunction(name: "skybox_vertex_shader")
        desc.fragmentFunction = library.makeFunction(name: "skybox_fragment_shader")
        desc.colorAttachments[0].pixelFormat = config.colorPixelFormat
        desc.depthAttachmentPixelFormat = config.depthPixelFormat
        desc.rasterSampleCount = config.sampleCount

        let pso = try device.makeRenderPipelineState(descriptor: desc)
        cachedPipelineState = pso
        return pso
    }
}
