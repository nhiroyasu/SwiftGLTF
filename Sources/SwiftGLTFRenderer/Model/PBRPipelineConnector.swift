import MetalKit
import SwiftGLTFParser
import SwiftGLTFCore
import SwiftGLTFShaderTypes

extension PBRVertexArgId {
    var index: Int {
        return Int(self.rawValue)
    }
}

class PBRPipelineConnector {
    private let device: MTLDevice
    private let vertexFunction: MTLFunction
    private let fragmentFunction: MTLFunction
    private let shaderConnection: ShaderConnection

    let opaquePSO: MTLRenderPipelineState
    let alphaBlendPSO: MTLRenderPipelineState

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
        self.opaquePSO = try device.makeRenderPipelineState(descriptor: opaqueDescriptor)

        // Transparent (premultiplied alpha blending)
        let alphaBlendDescriptor = opaqueDescriptor.copy() as! MTLRenderPipelineDescriptor
        let ca0 = alphaBlendDescriptor.colorAttachments[0]!
        ca0.isBlendingEnabled = true
        ca0.sourceRGBBlendFactor = .one
        ca0.destinationRGBBlendFactor = .oneMinusSourceAlpha
        ca0.rgbBlendOperation = .add
        ca0.sourceAlphaBlendFactor = .one
        ca0.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        ca0.alphaBlendOperation = .add
        self.alphaBlendPSO = try device.makeRenderPipelineState(descriptor: alphaBlendDescriptor)
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
        // Transmission/Thickness
        hasTransmissionTexture: UnsafePointer<Bool>,
        transmissionTexture: MTLTexture?,
        transmissionSampler: MTLSamplerState?,
        transmissionTexCoord: UnsafePointer<UInt32>,
        hasThicknessTexture: UnsafePointer<Bool>,
        thicknessTexture: MTLTexture?,
        thicknessSampler: MTLSamplerState?,
        thicknessTexCoord: UnsafePointer<UInt32>,
        // Specular
        hasSpecularTexture: UnsafePointer<Bool>,
        specularTexture: MTLTexture?,
        specularSampler: MTLSamplerState?,
        specularTexCoord: UnsafePointer<UInt32>,
        hasSpecularColorTexture: UnsafePointer<Bool>,
        specularColorTexture: MTLTexture?,
        specularColorSampler: MTLSamplerState?,
        specularColorTexCoord: UnsafePointer<UInt32>,
        // Sheen
        hasSheenColorTexture: UnsafePointer<Bool>,
        sheenColorTexture: MTLTexture?,
        sheenColorSampler: MTLSamplerState?,
        sheenColorTexCoord: UnsafePointer<UInt32>,
        hasSheenRoughnessTexture: UnsafePointer<Bool>,
        sheenRoughnessTexture: MTLTexture?,
        sheenRoughnessSampler: MTLSamplerState?,
        sheenRoughnessTexCoord: UnsafePointer<UInt32>,
        // Clearcoat
        hasClearcoatTexture: UnsafePointer<Bool>,
        clearcoatTexture: MTLTexture?,
        clearcoatSampler: MTLSamplerState?,
        clearcoatTexCoord: UnsafePointer<UInt32>,
        hasClearcoatRoughnessTexture: UnsafePointer<Bool>,
        clearcoatRoughnessTexture: MTLTexture?,
        clearcoatRoughnessSampler: MTLSamplerState?,
        clearcoatRoughnessTexCoord: UnsafePointer<UInt32>,
        hasClearcoatNormalTexture: UnsafePointer<Bool>,
        clearcoatNormalTexture: MTLTexture?,
        clearcoatNormalSampler: MTLSamplerState?,
        clearcoatNormalTexCoord: UnsafePointer<UInt32>,
        clearcoatNormalScale: UnsafePointer<Float>,
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

        // Transmission
        let hasTransmissionTextureAddr = encoder.constantData(at: 23)
        hasTransmissionTextureAddr.copyMemory(from: hasTransmissionTexture, byteCount: MemoryLayout<Bool>.size)
        encoder.setTexture(transmissionTexture, index: 24)
        encoder.setSamplerState(transmissionSampler, index: 25)
        let transmissionCoordAddr = encoder.constantData(at: 26)
        transmissionCoordAddr.copyMemory(from: transmissionTexCoord, byteCount: MemoryLayout<UInt32>.size)

        // Thickness
        let hasThicknessTextureAddr = encoder.constantData(at: 27)
        hasThicknessTextureAddr.copyMemory(from: hasThicknessTexture, byteCount: MemoryLayout<Bool>.size)
        encoder.setTexture(thicknessTexture, index: 28)
        encoder.setSamplerState(thicknessSampler, index: 29)
        let thicknessCoordAddr = encoder.constantData(at: 30)
        thicknessCoordAddr.copyMemory(from: thicknessTexCoord, byteCount: MemoryLayout<UInt32>.size)

        // Specular
        let hasSpecularTextureAddr = encoder.constantData(at: 31)
        hasSpecularTextureAddr.copyMemory(from: hasSpecularTexture, byteCount: MemoryLayout<Bool>.size)
        encoder.setTexture(specularTexture, index: 32)
        encoder.setSamplerState(specularSampler, index: 33)
        let specularCoordAddr = encoder.constantData(at: 34)
        specularCoordAddr.copyMemory(from: specularTexCoord, byteCount: MemoryLayout<UInt32>.size)

        let hasSpecularColorTextureAddr = encoder.constantData(at: 35)
        hasSpecularColorTextureAddr.copyMemory(from: hasSpecularColorTexture, byteCount: MemoryLayout<Bool>.size)
        encoder.setTexture(specularColorTexture, index: 36)
        encoder.setSamplerState(specularColorSampler, index: 37)
        let specularColorCoordAddr = encoder.constantData(at: 38)
        specularColorCoordAddr.copyMemory(from: specularColorTexCoord, byteCount: MemoryLayout<UInt32>.size)

        let hasSheenColorTextureAddr = encoder.constantData(at: 39)
        hasSheenColorTextureAddr.copyMemory(from: hasSheenColorTexture, byteCount: MemoryLayout<Bool>.size)
        encoder.setTexture(sheenColorTexture, index: 40)
        encoder.setSamplerState(sheenColorSampler, index: 41)
        let sheenColorCoordAddr = encoder.constantData(at: 42)
        sheenColorCoordAddr.copyMemory(from: sheenColorTexCoord, byteCount: MemoryLayout<UInt32>.size)

        let hasSheenRoughnessTextureAddr = encoder.constantData(at: 43)
        hasSheenRoughnessTextureAddr.copyMemory(from: hasSheenRoughnessTexture, byteCount: MemoryLayout<Bool>.size)
        encoder.setTexture(sheenRoughnessTexture, index: 44)
        encoder.setSamplerState(sheenRoughnessSampler, index: 45)
        let sheenRoughnessCoordAddr = encoder.constantData(at: 46)
        sheenRoughnessCoordAddr.copyMemory(from: sheenRoughnessTexCoord, byteCount: MemoryLayout<UInt32>.size)

        // Clearcoat
        let hasClearcoatTextureAddr = encoder.constantData(at: 47)
        hasClearcoatTextureAddr.copyMemory(from: hasClearcoatTexture, byteCount: MemoryLayout<Bool>.size)
        encoder.setTexture(clearcoatTexture, index: 48)
        encoder.setSamplerState(clearcoatSampler, index: 49)
        let clearcoatCoordAddr = encoder.constantData(at: 50)
        clearcoatCoordAddr.copyMemory(from: clearcoatTexCoord, byteCount: MemoryLayout<UInt32>.size)

        let hasClearcoatRoughnessTextureAddr = encoder.constantData(at: 51)
        hasClearcoatRoughnessTextureAddr.copyMemory(from: hasClearcoatRoughnessTexture, byteCount: MemoryLayout<Bool>.size)
        encoder.setTexture(clearcoatRoughnessTexture, index: 52)
        encoder.setSamplerState(clearcoatRoughnessSampler, index: 53)
        let clearcoatRoughnessCoordAddr = encoder.constantData(at: 54)
        clearcoatRoughnessCoordAddr.copyMemory(from: clearcoatRoughnessTexCoord, byteCount: MemoryLayout<UInt32>.size)

        let hasClearcoatNormalTextureAddr = encoder.constantData(at: 55)
        hasClearcoatNormalTextureAddr.copyMemory(from: hasClearcoatNormalTexture, byteCount: MemoryLayout<Bool>.size)
        encoder.setTexture(clearcoatNormalTexture, index: 56)
        encoder.setSamplerState(clearcoatNormalSampler, index: 57)
        let clearcoatNormalCoordAddr = encoder.constantData(at: 58)
        clearcoatNormalCoordAddr.copyMemory(from: clearcoatNormalTexCoord, byteCount: MemoryLayout<UInt32>.size)

        let clearcoatNormalScaleAddr = encoder.constantData(at: 59)
        clearcoatNormalScaleAddr.copyMemory(from: clearcoatNormalScale, byteCount: MemoryLayout<Float>.size)
        return buffer
    }

    func makeEnvMapArgBuffer(
        prefilterEnvMap: MTLTexture,
        irradianceMap: MTLTexture,
        brdfLUT: MTLTexture,
        prefilterSheenMap: MTLTexture
    ) throws -> MTLBuffer {
        let encoder = fragmentFunction.makeArgumentEncoder(bufferIndex: 1)
        let buffer = device.makeBuffer(length: encoder.encodedLength, options: .storageModeShared)!
        encoder.setArgumentBuffer(buffer, offset: 0)
        encoder.setTexture(prefilterEnvMap, index: 0)
        encoder.setTexture(irradianceMap, index: 1)
        encoder.setTexture(brdfLUT, index: 2)
        encoder.setTexture(prefilterSheenMap, index: 3)

        return buffer
    }

    func makeScreenColorArgBuffer(
        sceneColor: MTLTexture,
        sceneColorSampler: MTLSamplerState
    ) -> MTLBuffer {
        let encoder = fragmentFunction.makeArgumentEncoder(bufferIndex: 3)
        let buffer = device.makeBuffer(length: encoder.encodedLength, options: .storageModeShared)!
        encoder.setArgumentBuffer(buffer, offset: 0)
        encoder.setTexture(sceneColor, index: 0)
        encoder.setSamplerState(sceneColorSampler, index: 1)
        let flagAddr = encoder.constantData(at: 2)
        var useSceneColor = true
        flagAddr.copyMemory(from: &useSceneColor, byteCount: MemoryLayout<Bool>.size)
        return buffer
    }

    func makeScreenColorArgDummy() -> MTLBuffer {
        let encoder = fragmentFunction.makeArgumentEncoder(bufferIndex: 3)
        let buffer = device.makeBuffer(length: encoder.encodedLength, options: .storageModeShared)!
        encoder.setArgumentBuffer(buffer, offset: 0)

        let flagAddr = encoder.constantData(at: 2)
        var useSceneColor: Bool = false
        flagAddr.copyMemory(from: &useSceneColor, byteCount: MemoryLayout<Bool>.size)
        return buffer
    }

    func getVertexArgumentsSize() -> Int {
        let encoder = vertexFunction.makeArgumentEncoder(bufferIndex: 1)
        return encoder.encodedLength
    }

    func makeVertexArgumentsBuffer(
        modelBuffer: MTLBuffer,
        inverseModelBuffer: MTLBuffer,
        // Morph (optional, up to 8 targets)
        morphTargetCount: UInt32 = 0,
        morphWeightsBuffer: MTLBuffer? = nil,
        morphInterleavedBuffers: [MTLBuffer] = [],
        transformIndex: Int,
        skinDispatch: SkinDispatch?,
        morphDispatchIndex: Int
    ) throws -> MTLBuffer {
        let encoder = vertexFunction.makeArgumentEncoder(bufferIndex: 1)
        guard let buffer = device.makeBuffer(length: encoder.encodedLength, options: [.storageModeShared]) else {
            throw SwiftGLTFError.makeRender(.argumentBufferCreateFailed, context: .capture(stage: .render))
        }
        encoder.setArgumentBuffer(buffer, offset: 0)

        encoder.setBuffer(modelBuffer, offset: 0, index: PBRVertexArgIdModel.index)
        encoder.setBuffer(inverseModelBuffer, offset: 0, index: PBRVertexArgIdInverseModel.index)

        // Morph
        var targetCountVar = morphTargetCount
        let targetCountAddr = encoder.constantData(at: PBRVertexArgIdMorphTargetCount.index)
        targetCountAddr.copyMemory(from: &targetCountVar, byteCount: MemoryLayout<UInt32>.size)
        encoder.setBuffer(morphWeightsBuffer, offset: 0, index: PBRVertexArgIdMorphDefaultWeights.index)
        // Up to 8 targets
        let maxTargets = 8
        for i in 0..<min(maxTargets, morphInterleavedBuffers.count) {
            encoder.setBuffer(morphInterleavedBuffers[i], offset: 0, index: PBRVertexArgIdMorphInterleaved0.index + i)
        }

        var transformIndex = transformIndex
        let transformIndexAddr = encoder.constantData(at: PBRVertexArgIdTransformIndex.index)
        transformIndexAddr.copyMemory(from: &transformIndex, byteCount: MemoryLayout<Int>.size)
        var skinDispatch = skinDispatch
        let skinDispatchAddr = encoder.constantData(at: PBRVertexArgIdSkinDispatch.index)
        skinDispatchAddr.copyMemory(from: &skinDispatch, byteCount: MemoryLayout<SkinDispatch>.size)
        var morphDispatchIndex = morphDispatchIndex
        let morphDispatchIndexAddr = encoder.constantData(at: PBRVertexArgIdMorphDispatchIndex.index)
        morphDispatchIndexAddr.copyMemory(from: &morphDispatchIndex, byteCount: MemoryLayout<Int>.size)

        return buffer
    }
}
