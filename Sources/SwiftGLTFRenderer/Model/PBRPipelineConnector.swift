import MetalKit
import SwiftGLTFParser

class PBRPipelineConnector {
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
        self.vertexFunction = library.makeFunction(name: "pbr_vertex_shader")!
        self.fragmentFunction = library.makeFunction(name: "pbr_fragment_shader")!

        let psoDescriptor = MTLRenderPipelineDescriptor()
        psoDescriptor.vertexFunction = vertexFunction
        psoDescriptor.fragmentFunction = fragmentFunction
        psoDescriptor.colorAttachments[0].pixelFormat = config.colorPixelFormat
        psoDescriptor.depthAttachmentPixelFormat = config.depthPixelFormat
        psoDescriptor.rasterSampleCount = config.sampleCount
        psoDescriptor.vertexDescriptor = makeGLTFVertexDescriptor()
        self.pipelineState = try device.makeRenderPipelineState(descriptor: psoDescriptor)
    }

    func makeFragmentArgumentBuffer(
        materialUniformsBuffer: MTLBuffer,
        hasBaseColorTexture: UnsafePointer<Bool>,
        baseColorTexture: MTLTexture?,
        baseColorSampler: MTLSamplerState?,
        hasNormalTexture: UnsafePointer<Bool>,
        normalTexture: MTLTexture?,
        normalSampler: MTLSamplerState?,
        hasMetallicRoughnessTexture: UnsafePointer<Bool>,
        metallicRoughnessTexture: MTLTexture?,
        metallicRoughnessSampler: MTLSamplerState?,
        hasEmissiveTexture: UnsafePointer<Bool>,
        emissiveTexture: MTLTexture?,
        emissiveSampler: MTLSamplerState?,
        hasOcclusionTexture: UnsafePointer<Bool>,
        occlusionTexture: MTLTexture?,
        occlusionSampler: MTLSamplerState?,
        // Texture coordinate indices
        baseColorTexCoord: UnsafePointer<UInt32>,
        normalTexCoord: UnsafePointer<UInt32>,
        metallicRoughnessTexCoord: UnsafePointer<UInt32>,
        emissiveTexCoord: UnsafePointer<UInt32>,
        occlusionTexCoord: UnsafePointer<UInt32>
    ) throws -> MTLBuffer {
        let encoder = fragmentFunction.makeArgumentEncoder(bufferIndex: 0)
        guard let buffer = device.makeBuffer(length: encoder.encodedLength, options: [.storageModeShared]) else {
            throw NSError(domain: "PBRPipelineStateLoader", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create argument buffer"])
        }
        encoder.setArgumentBuffer(buffer, offset: 0)

        encoder.setBuffer(materialUniformsBuffer, offset: 0, index: 0)
        let hasBaseColorTextureAddr = encoder.constantData(at: 1)
        hasBaseColorTextureAddr.copyMemory(from: hasBaseColorTexture, byteCount: MemoryLayout<Bool>.size)
        encoder.setTexture(baseColorTexture, index: 2)
        encoder.setSamplerState(baseColorSampler, index: 3)
        let baseColorCoordAddr = encoder.constantData(at: 4)
        baseColorCoordAddr.copyMemory(from: baseColorTexCoord, byteCount: MemoryLayout<UInt32>.size)

        let hasNormalTextureAddr = encoder.constantData(at: 5)
        hasNormalTextureAddr.copyMemory(from: hasNormalTexture, byteCount: MemoryLayout<Bool>.size)
        encoder.setTexture(normalTexture, index: 6)
        encoder.setSamplerState(normalSampler, index: 7)
        let normalCoordAddr = encoder.constantData(at: 8)
        normalCoordAddr.copyMemory(from: normalTexCoord, byteCount: MemoryLayout<UInt32>.size)

        let hasMetallicRoughnessTextureAddr = encoder.constantData(at: 9)
        hasMetallicRoughnessTextureAddr.copyMemory(from: hasMetallicRoughnessTexture, byteCount: MemoryLayout<Bool>.size)
        encoder.setTexture(metallicRoughnessTexture, index: 10)
        encoder.setSamplerState(metallicRoughnessSampler, index: 11)
        let mrcCoordAddr = encoder.constantData(at: 12)
        mrcCoordAddr.copyMemory(from: metallicRoughnessTexCoord, byteCount: MemoryLayout<UInt32>.size)

        let hasEmissiveTextureAddr = encoder.constantData(at: 13)
        hasEmissiveTextureAddr.copyMemory(from: hasEmissiveTexture, byteCount: MemoryLayout<Bool>.size)
        encoder.setTexture(emissiveTexture, index: 14)
        encoder.setSamplerState(emissiveSampler, index: 15)
        let emissiveCoordAddr = encoder.constantData(at: 16)
        emissiveCoordAddr.copyMemory(from: emissiveTexCoord, byteCount: MemoryLayout<UInt32>.size)

        let hasOcclusionTextureAddr = encoder.constantData(at: 17)
        hasOcclusionTextureAddr.copyMemory(from: hasOcclusionTexture, byteCount: MemoryLayout<Bool>.size)
        encoder.setTexture(occlusionTexture, index: 18)
        encoder.setSamplerState(occlusionSampler, index: 19)
        let occlusionCoordAddr = encoder.constantData(at: 20)
        occlusionCoordAddr.copyMemory(from: occlusionTexCoord, byteCount: MemoryLayout<UInt32>.size)
        return buffer
    }

    func makeEnvMapArgBuffer(
        prefilterEnvMap: MTLTexture,
        irradianceMap: MTLTexture,
        brdfLUT: MTLTexture
    ) throws -> MTLBuffer {
        let encoder = fragmentFunction.makeArgumentEncoder(bufferIndex: 1)
        let buffer = device.makeBuffer(length: encoder.encodedLength, options: .storageModeShared)!
        encoder.setArgumentBuffer(buffer, offset: 0)
        encoder.setTexture(prefilterEnvMap, index: 0)
        encoder.setTexture(irradianceMap, index: 1)
        encoder.setTexture(brdfLUT, index: 2)

        return buffer
    }
}
