import MetalKit

/// Configuration for skybox pipeline state.
public struct SkyboxPipelineConfig {
    public let sampleCount: Int
    public let colorPixelFormat: MTLPixelFormat
    public let depthPixelFormat: MTLPixelFormat

    public init(
        sampleCount: Int = 1,
        colorPixelFormat: MTLPixelFormat = .rgba8Unorm_srgb,
        depthPixelFormat: MTLPixelFormat = .depth32Float
    ) {
        self.sampleCount = sampleCount
        self.colorPixelFormat = colorPixelFormat
        self.depthPixelFormat = depthPixelFormat
    }
}

/// Loader to create a SkyboxMesh with its pipeline and buffers.
public class SkyboxMeshLoader {
    private let device: MTLDevice
    private let pso: MTLRenderPipelineState
    private let dso: MTLDepthStencilState

    /// Initialize loader with device, shader library, pixel formats and sample count.
    /// - Parameters:
    ///   - device: MTLDevice to create buffers and pipeline state.
    ///   - library: MTLLibrary containing skybox shaders.
    ///   - colorPixelFormat: Pixel format of render target.
    ///   - depthPixelFormat: Pixel format for depth attachment.
    ///   - sampleCount: Multisample count (default 1).
    /// Initialize loader with device, shader library and pipeline configuration.
    /// - Parameters:
    ///   - device: MTLDevice to create buffers and pipeline state.
    ///   - library: MTLLibrary containing skybox shaders.
    ///   - config: Pipeline configuration for skybox rendering.
    public init(
        device: MTLDevice,
        library: MTLLibrary,
        config: SkyboxPipelineConfig
    ) async throws {
        self.device = device
        // Pipeline state
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = library.makeFunction(name: "skybox_vertex_shader")
        desc.fragmentFunction = library.makeFunction(name: "skybox_fragment_shader")
        desc.colorAttachments[0].pixelFormat = config.colorPixelFormat
        desc.depthAttachmentPixelFormat = config.depthPixelFormat
        desc.rasterSampleCount = config.sampleCount
        self.pso = try await device.makeRenderPipelineState(descriptor: desc)
        // Depth stencil state
        let dsd = MTLDepthStencilDescriptor()
        dsd.depthCompareFunction = .always
        dsd.isDepthWriteEnabled = false
        self.dso = device.makeDepthStencilState(descriptor: dsd)!
    }

    /// Create and return a SkyboxMesh with buffers and pipeline configured.
    func loadMesh() -> SkyboxMesh {
        // Vertex and index buffers from static data
        let vbuf = device.makeBuffer(
            bytes: skyboxVertices,
            length: MemoryLayout<Float>.size * skyboxVertices.count,
            options: .storageModeShared
        )!
        let ibuf = device.makeBuffer(
            bytes: skyboxIndices,
            length: MemoryLayout<UInt16>.size * skyboxIndices.count,
            options: .storageModeShared
        )!
        return SkyboxMesh(
            vertexBuffer: vbuf,
            indexBuffer: ibuf,
            indexCount: skyboxIndices.count,
            indexType: .uint16,
            pso: pso,
            dso: dso
        )
    }
}
