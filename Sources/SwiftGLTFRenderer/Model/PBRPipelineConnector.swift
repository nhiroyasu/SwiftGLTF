import MetalKit
import SwiftGLTFParser
import SwiftGLTFCore
import SwiftGLTFShaderTypes

class PBRPipelineConnector {
    private let device: MTLDevice
    private let vertexFunction: MTLFunction
    private let fragmentFunction: MTLFunction
    private let shaderConnection: ShaderConnection

    let pipelineStateOpaque: MTLRenderPipelineState
    let pipelineStateTransparent: MTLRenderPipelineState

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

        // Opaque / Mask (no blending)
        let opaqueDescriptor = MTLRenderPipelineDescriptor()
        opaqueDescriptor.vertexFunction = vertexFunction
        opaqueDescriptor.fragmentFunction = fragmentFunction
        opaqueDescriptor.colorAttachments[0].pixelFormat = config.colorPixelFormat
        opaqueDescriptor.depthAttachmentPixelFormat = config.depthPixelFormat
        opaqueDescriptor.rasterSampleCount = config.sampleCount
        opaqueDescriptor.vertexDescriptor = makeGLTFVertexDescriptor()
        self.pipelineStateOpaque = try device.makeRenderPipelineState(descriptor: opaqueDescriptor)

        // Transparent (premultiplied alpha blending)
        let transparentDescriptor = opaqueDescriptor.copy() as! MTLRenderPipelineDescriptor
        let ca0 = transparentDescriptor.colorAttachments[0]!
        ca0.isBlendingEnabled = true
        ca0.sourceRGBBlendFactor = .one
        ca0.destinationRGBBlendFactor = .oneMinusSourceAlpha
        ca0.rgbBlendOperation = .add
        ca0.sourceAlphaBlendFactor = .one
        ca0.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        ca0.alphaBlendOperation = .add
        self.pipelineStateTransparent = try device.makeRenderPipelineState(descriptor: transparentDescriptor)
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
        occlusionTexCoord: UnsafePointer<UInt32>,
        // Alpha params
        alphaMode: UnsafePointer<UInt32>,
        alphaCutoff: UnsafePointer<Float>
    ) throws -> MTLBuffer {
        let encoder = fragmentFunction.makeArgumentEncoder(bufferIndex: 0)
        guard let buffer = device.makeBuffer(length: encoder.encodedLength, options: [.storageModeShared]) else {
            throw SwiftGLTFError.makeRender(.argumentBufferCreateFailed, context: .capture(stage: .render))
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

        // Alpha params
        let alphaModeAddr = encoder.constantData(at: 21)
        alphaModeAddr.copyMemory(from: alphaMode, byteCount: MemoryLayout<UInt32>.size)
        let alphaCutoffAddr = encoder.constantData(at: 22)
        alphaCutoffAddr.copyMemory(from: alphaCutoff, byteCount: MemoryLayout<Float>.size)
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

    func getVertexArgumentsSize() -> Int {
        let encoder = vertexFunction.makeArgumentEncoder(bufferIndex: 1)
        return encoder.encodedLength
    }

    func makeVertexArgumentsBuffer(
        model: UnsafePointer<simd_float4x4>,
        inverseModel: UnsafePointer<simd_float4x4>,
        hasSkinning: UnsafePointer<Bool>,
        globalJointMatricesBuffer: MTLBuffer?,
        // Morph (optional, up to 8 targets)
        hasMorph: Bool = false,
        morphTargetCount: UInt32 = 0,
        morphWeightsBuffer: MTLBuffer? = nil,
        morphInterleavedBuffers: [MTLBuffer] = []
    ) throws -> MTLBuffer {
        let encoder = vertexFunction.makeArgumentEncoder(bufferIndex: 1)
        guard let buffer = device.makeBuffer(length: encoder.encodedLength, options: [.storageModeShared]) else {
            throw SwiftGLTFError.makeRender(.argumentBufferCreateFailed, context: .capture(stage: .render))
        }
        encoder.setArgumentBuffer(buffer, offset: 0)

        let modelAddr = encoder.constantData(at: 0)
        modelAddr.copyMemory(from: model, byteCount: MemoryLayout<simd_float4x4>.size)

        let inverseModelAddr = encoder.constantData(at: 1)
        inverseModelAddr.copyMemory(from: inverseModel, byteCount: MemoryLayout<simd_float4x4>.size)

        let hasSkinningAddr = encoder.constantData(at: 2)
        hasSkinningAddr.copyMemory(from: hasSkinning, byteCount: MemoryLayout<Bool>.size)

        encoder.setBuffer(globalJointMatricesBuffer, offset: 0, index: 3)

        // Morph
        var hasMorphVar = hasMorph
        let hasMorphAddr = encoder.constantData(at: 4)
        hasMorphAddr.copyMemory(from: &hasMorphVar, byteCount: MemoryLayout<Bool>.size)
        var targetCountVar = morphTargetCount
        let targetCountAddr = encoder.constantData(at: 5)
        targetCountAddr.copyMemory(from: &targetCountVar, byteCount: MemoryLayout<UInt32>.size)
        encoder.setBuffer(morphWeightsBuffer, offset: 0, index: 6)
        // Up to 8 targets
        let maxTargets = 8
        for i in 0..<min(maxTargets, morphInterleavedBuffers.count) {
            encoder.setBuffer(morphInterleavedBuffers[i], offset: 0, index: 7 + i)
        }
        return buffer
    }
}
