import MetalKit
import OSLog

public class WireframePipelineStateLoader {
    private let device: MTLDevice
    private let library: MTLLibrary
    private let config: PipelineStateLoaderConfig

    private let vertexFunction: MTLFunction
    private let fragmentFunction: MTLFunction
    private var cachedPipelineStates: [MDLVertexDescriptor: MTLRenderPipelineState] = [:]

    public init(
        device: MTLDevice,
        library: MTLLibrary,
        config: PipelineStateLoaderConfig = PipelineStateLoaderConfig()
    ) {
        self.device = device
        self.library = library
        self.config = config
        self.vertexFunction = library.makeFunction(name: "wireframe_vertex_shader")!
        self.fragmentFunction = library.makeFunction(name: "wireframe_shader")!
    }

    func load(
        for vertexDescriptor: MDLVertexDescriptor,
        useCache: Bool = true
    ) throws -> MTLRenderPipelineState {
        if useCache, let cachedState = cachedPipelineStates[vertexDescriptor] {
            return cachedState
        }

        // Validate the vertex descriptor
        try validate(for: vertexDescriptor)

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vertexFunction
        desc.fragmentFunction = fragmentFunction
        desc.colorAttachments[0].pixelFormat = config.colorPixelFormat
        desc.depthAttachmentPixelFormat = config.depthPixelFormat
        desc.rasterSampleCount = config.sampleCount
        desc.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(vertexDescriptor)

        let pso = try device.makeRenderPipelineState(descriptor: desc)
        cachedPipelineStates[vertexDescriptor] = pso
        return pso
    }

    func validate(for vertexDescriptor: MDLVertexDescriptor) throws {
        // Validate the vertex descriptor
        // Ensure it has a position attribute at index 0
        guard let firstAttr = vertexDescriptor.attributes[0] as? MDLVertexAttribute else {
            throw NSError(domain: "WireframePipelineStateLoader", code: 0, userInfo: [NSLocalizedDescriptionKey: "Vertex descriptor must have at least one attribute."])
        }
        guard firstAttr.name == MDLVertexAttributePosition else {
            throw NSError(domain: "WireframePipelineStateLoader", code: 1, userInfo: [NSLocalizedDescriptionKey: "First attribute must be position."])
        }

        // Ensure the position attribute is of float3 format
        guard firstAttr.format == .float3 else {
            throw NSError(domain: "WireframePipelineStateLoader", code: 2, userInfo: [NSLocalizedDescriptionKey: "Position attribute must be of format float3."])
        }

        return
    }
}
