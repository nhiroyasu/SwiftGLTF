import MetalKit
import SwiftGLTFParser
import SwiftGLTFCore

class WireframePipelineConnector {
    private let device: MTLDevice
    private let vertexFunction: MTLFunction
    private let fragmentFunction: MTLFunction
    private let shaderConnection: ShaderConnection

    let pipelineState: MTLRenderPipelineState

    init(
        device: MTLDevice,
        library: MTLLibrary,
        config: PipelineStateLoaderConfig,
        shaderConnection: ShaderConnection
    ) throws {
        self.device = device
        self.shaderConnection = shaderConnection
        self.vertexFunction = library.makeFunction(name: "wireframe_vertex_shader")!
        self.fragmentFunction = library.makeFunction(name: "wireframe_fragment_shader")!

        let psoDescriptor = MTLRenderPipelineDescriptor()
        psoDescriptor.vertexFunction = vertexFunction
        psoDescriptor.fragmentFunction = fragmentFunction
        psoDescriptor.colorAttachments[0].pixelFormat = config.colorPixelFormat
        psoDescriptor.depthAttachmentPixelFormat = config.depthPixelFormat
        psoDescriptor.rasterSampleCount = config.sampleCount
        psoDescriptor.vertexDescriptor = makeGLTFVertexDescriptor()
        self.pipelineState = try device.makeRenderPipelineState(descriptor: psoDescriptor)
    }

    func makeVertexArgumentsBuffer(
        model: UnsafePointer<simd_float4x4>
    ) throws -> MTLBuffer {
        let encoder = vertexFunction.makeArgumentEncoder(bufferIndex: 1)
        guard let buffer = device.makeBuffer(length: encoder.encodedLength, options: [.storageModeShared]) else {
            throw SwiftGLTFError.makeRender(.argumentBufferCreateFailed, context: .capture(stage: .render))
        }
        encoder.setArgumentBuffer(buffer, offset: 0)

        let modelAddr = encoder.constantData(at: 0)
        modelAddr.copyMemory(from: model, byteCount: MemoryLayout<simd_float4x4>.size)

        return buffer
    }
}
