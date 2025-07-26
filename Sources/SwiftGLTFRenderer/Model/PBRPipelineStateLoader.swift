import MetalKit
import OSLog
import SwiftGLTF

public class PBRPipelineStateLoader {
    private let device: MTLDevice
    private let library: MTLLibrary
    private let config: PipelineStateLoaderConfig

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
        self.fragmentFunction = library.makeFunction(name: "pbr_shader")!
    }

    func load(
        for vertexDescriptor: MDLVertexDescriptor,
        useCache: Bool = true
    ) throws -> MTLRenderPipelineState {
        if useCache, let cachedState = cachedPipelineStates[vertexDescriptor] {
            return cachedState
        }

        let psoDescriptor = MTLRenderPipelineDescriptor()
        psoDescriptor.vertexFunction = try decideVertexShader(from: vertexDescriptor)
        psoDescriptor.fragmentFunction = fragmentFunction
        psoDescriptor.colorAttachments[0].pixelFormat = config.colorPixelFormat
        psoDescriptor.depthAttachmentPixelFormat = config.depthPixelFormat
        psoDescriptor.rasterSampleCount = config.sampleCount
        psoDescriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(vertexDescriptor)

        let pso = try device.makeRenderPipelineState(descriptor: psoDescriptor)
        cachedPipelineStates[vertexDescriptor] = pso
        return pso
    }

    private func decideVertexShader(from vertexDescriptor: MDLVertexDescriptor) throws -> MTLFunction {
        // Validate that required attributes exist
        guard
            vertexDescriptor.attributes[GLTFVertexAttributeIndex.POSITION] as? MDLVertexAttribute != nil,
            vertexDescriptor.attributes[GLTFVertexAttributeIndex.NORMAL] as? MDLVertexAttribute != nil,
            vertexDescriptor.attributes[GLTFVertexAttributeIndex.TANGENT] as? MDLVertexAttribute != nil
        else {
            throw NSError(
                domain: "MDLAssetLoader",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Required vertex attributes are missing"]
            )
        }

        os_log("⬇️ Loading unified PBR shader")
        return library.makeFunction(name: "pbr_vertex_shader")!
    }
}
