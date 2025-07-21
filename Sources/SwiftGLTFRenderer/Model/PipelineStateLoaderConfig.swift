import MetalKit

public struct PipelineStateLoaderConfig {
    public let sampleCount: Int
    public let colorPixelFormat: MTLPixelFormat
    public let depthPixelFormat: MTLPixelFormat

    public init(
        sampleCount: Int = 4,
        colorPixelFormat: MTLPixelFormat = .rgba16Float,
        depthPixelFormat: MTLPixelFormat = .depth32Float
    ) {
        self.sampleCount = sampleCount
        self.colorPixelFormat = colorPixelFormat
        self.depthPixelFormat = depthPixelFormat
    }
}
