import MetalKit

/// Configuration for skybox pipeline state.
public struct SkyboxPipelineConfig {
    public let sampleCount: Int
    public let colorPixelFormat: MTLPixelFormat
    public let depthPixelFormat: MTLPixelFormat
    public let usesBloomSourceAttachment: Bool

    public init(
        sampleCount: Int = 1,
        colorPixelFormat: MTLPixelFormat = .rgba8Unorm_srgb,
        depthPixelFormat: MTLPixelFormat = .depth32Float,
        usesBloomSourceAttachment: Bool = false
    ) {
        self.sampleCount = sampleCount
        self.colorPixelFormat = colorPixelFormat
        self.depthPixelFormat = depthPixelFormat
        self.usesBloomSourceAttachment = usesBloomSourceAttachment
    }
}

/// Loader to create a SkyboxMesh with its pipeline and buffers.
public class SkyboxMeshLoader {
    private let device: MTLDevice

    public init(device: MTLDevice) throws {
        self.device = device
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
            indexType: .uint16
        )
    }
}
