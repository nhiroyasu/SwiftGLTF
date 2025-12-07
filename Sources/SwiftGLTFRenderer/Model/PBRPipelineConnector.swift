import MetalKit
import SwiftGLTFParser
import SwiftGLTFCore
import SwiftGLTFShaderTypes

extension PBRVertexArgId {
    var index: Int {
        return Int(self.rawValue)
    }
}

public class PBRPipelineConnector {
    private let device: MTLDevice
    private let vertexFunction: MTLFunction
    private let fragmentFunction: MTLFunction
    private let shaderConnection: ShaderConnection

    let opaquePSO: MTLRenderPipelineState
    let alphaBlendPSO: MTLRenderPipelineState

    public init(
        device: MTLDevice,
        config: PipelineStateLoaderConfig = .init(
            sampleCount: 4,
            colorPixelFormat: .rgba16Float,
            depthPixelFormat: .depth32Float
        ),
        shaderConnection: ShaderConnection
    ) throws {
        self.device = device
        self.shaderConnection = shaderConnection
        let library = try device.makePackageLibrary()
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
        opaqueDescriptor.supportIndirectCommandBuffers = true
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

    func setFragmentArgumentArrayBuffer(
        encoder: MTLArgumentEncoder,
        buffer: MTLBuffer,
        argIndex: Int,
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
        alphaCutoff: UnsafePointer<Float>,
        baseColorTransformOffsetScale: UnsafePointer<SIMD4<Float>>,
        baseColorTransformRotation: UnsafePointer<Float>,
        normalTransformOffsetScale: UnsafePointer<SIMD4<Float>>,
        normalTransformRotation: UnsafePointer<Float>,
        metallicRoughnessTransformOffsetScale: UnsafePointer<SIMD4<Float>>,
        metallicRoughnessTransformRotation: UnsafePointer<Float>,
        emissiveTransformOffsetScale: UnsafePointer<SIMD4<Float>>,
        emissiveTransformRotation: UnsafePointer<Float>,
        occlusionTransformOffsetScale: UnsafePointer<SIMD4<Float>>,
        occlusionTransformRotation: UnsafePointer<Float>,
        transmissionTransformOffsetScale: UnsafePointer<SIMD4<Float>>,
        transmissionTransformRotation: UnsafePointer<Float>,
        thicknessTransformOffsetScale: UnsafePointer<SIMD4<Float>>,
        thicknessTransformRotation: UnsafePointer<Float>,
        specularTransformOffsetScale: UnsafePointer<SIMD4<Float>>,
        specularTransformRotation: UnsafePointer<Float>,
        specularColorTransformOffsetScale: UnsafePointer<SIMD4<Float>>,
        specularColorTransformRotation: UnsafePointer<Float>,
        sheenColorTransformOffsetScale: UnsafePointer<SIMD4<Float>>,
        sheenColorTransformRotation: UnsafePointer<Float>,
        sheenRoughnessTransformOffsetScale: UnsafePointer<SIMD4<Float>>,
        sheenRoughnessTransformRotation: UnsafePointer<Float>,
        clearcoatTransformOffsetScale: UnsafePointer<SIMD4<Float>>,
        clearcoatTransformRotation: UnsafePointer<Float>,
        clearcoatRoughnessTransformOffsetScale: UnsafePointer<SIMD4<Float>>,
        clearcoatRoughnessTransformRotation: UnsafePointer<Float>,
        clearcoatNormalTransformOffsetScale: UnsafePointer<SIMD4<Float>>,
        clearcoatNormalTransformRotation: UnsafePointer<Float>
    ) throws {
        let argSize = encoder.encodedLength
        encoder.setArgumentBuffer(buffer, offset: argSize * argIndex)

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
        let baseColorTransformOffsetScaleAddr = encoder.constantData(at: 60)
        baseColorTransformOffsetScaleAddr.copyMemory(from: baseColorTransformOffsetScale, byteCount: MemoryLayout<SIMD4<Float>>.size)
        let baseColorTransformRotationAddr = encoder.constantData(at: 61)
        baseColorTransformRotationAddr.copyMemory(from: baseColorTransformRotation, byteCount: MemoryLayout<Float>.size)
        let normalTransformOffsetScaleAddr = encoder.constantData(at: 62)
        normalTransformOffsetScaleAddr.copyMemory(from: normalTransformOffsetScale, byteCount: MemoryLayout<SIMD4<Float>>.size)
        let normalTransformRotationAddr = encoder.constantData(at: 63)
        normalTransformRotationAddr.copyMemory(from: normalTransformRotation, byteCount: MemoryLayout<Float>.size)
        let metallicRoughnessTransformOffsetScaleAddr = encoder.constantData(at: 64)
        metallicRoughnessTransformOffsetScaleAddr.copyMemory(from: metallicRoughnessTransformOffsetScale, byteCount: MemoryLayout<SIMD4<Float>>.size)
        let metallicRoughnessTransformRotationAddr = encoder.constantData(at: 65)
        metallicRoughnessTransformRotationAddr.copyMemory(from: metallicRoughnessTransformRotation, byteCount: MemoryLayout<Float>.size)
        let emissiveTransformOffsetScaleAddr = encoder.constantData(at: 66)
        emissiveTransformOffsetScaleAddr.copyMemory(from: emissiveTransformOffsetScale, byteCount: MemoryLayout<SIMD4<Float>>.size)
        let emissiveTransformRotationAddr = encoder.constantData(at: 67)
        emissiveTransformRotationAddr.copyMemory(from: emissiveTransformRotation, byteCount: MemoryLayout<Float>.size)
        let occlusionTransformOffsetScaleAddr = encoder.constantData(at: 68)
        occlusionTransformOffsetScaleAddr.copyMemory(from: occlusionTransformOffsetScale, byteCount: MemoryLayout<SIMD4<Float>>.size)
        let occlusionTransformRotationAddr = encoder.constantData(at: 69)
        occlusionTransformRotationAddr.copyMemory(from: occlusionTransformRotation, byteCount: MemoryLayout<Float>.size)
        let transmissionTransformOffsetScaleAddr = encoder.constantData(at: 70)
        transmissionTransformOffsetScaleAddr.copyMemory(from: transmissionTransformOffsetScale, byteCount: MemoryLayout<SIMD4<Float>>.size)
        let transmissionTransformRotationAddr = encoder.constantData(at: 71)
        transmissionTransformRotationAddr.copyMemory(from: transmissionTransformRotation, byteCount: MemoryLayout<Float>.size)
        let thicknessTransformOffsetScaleAddr = encoder.constantData(at: 72)
        thicknessTransformOffsetScaleAddr.copyMemory(from: thicknessTransformOffsetScale, byteCount: MemoryLayout<SIMD4<Float>>.size)
        let thicknessTransformRotationAddr = encoder.constantData(at: 73)
        thicknessTransformRotationAddr.copyMemory(from: thicknessTransformRotation, byteCount: MemoryLayout<Float>.size)
        let specularTransformOffsetScaleAddr = encoder.constantData(at: 74)
        specularTransformOffsetScaleAddr.copyMemory(from: specularTransformOffsetScale, byteCount: MemoryLayout<SIMD4<Float>>.size)
        let specularTransformRotationAddr = encoder.constantData(at: 75)
        specularTransformRotationAddr.copyMemory(from: specularTransformRotation, byteCount: MemoryLayout<Float>.size)
        let specularColorTransformOffsetScaleAddr = encoder.constantData(at: 76)
        specularColorTransformOffsetScaleAddr.copyMemory(from: specularColorTransformOffsetScale, byteCount: MemoryLayout<SIMD4<Float>>.size)
        let specularColorTransformRotationAddr = encoder.constantData(at: 77)
        specularColorTransformRotationAddr.copyMemory(from: specularColorTransformRotation, byteCount: MemoryLayout<Float>.size)
        let sheenColorTransformOffsetScaleAddr = encoder.constantData(at: 78)
        sheenColorTransformOffsetScaleAddr.copyMemory(from: sheenColorTransformOffsetScale, byteCount: MemoryLayout<SIMD4<Float>>.size)
        let sheenColorTransformRotationAddr = encoder.constantData(at: 79)
        sheenColorTransformRotationAddr.copyMemory(from: sheenColorTransformRotation, byteCount: MemoryLayout<Float>.size)
        let sheenRoughnessTransformOffsetScaleAddr = encoder.constantData(at: 80)
        sheenRoughnessTransformOffsetScaleAddr.copyMemory(from: sheenRoughnessTransformOffsetScale, byteCount: MemoryLayout<SIMD4<Float>>.size)
        let sheenRoughnessTransformRotationAddr = encoder.constantData(at: 81)
        sheenRoughnessTransformRotationAddr.copyMemory(from: sheenRoughnessTransformRotation, byteCount: MemoryLayout<Float>.size)
        let clearcoatTransformOffsetScaleAddr = encoder.constantData(at: 82)
        clearcoatTransformOffsetScaleAddr.copyMemory(from: clearcoatTransformOffsetScale, byteCount: MemoryLayout<SIMD4<Float>>.size)
        let clearcoatTransformRotationAddr = encoder.constantData(at: 83)
        clearcoatTransformRotationAddr.copyMemory(from: clearcoatTransformRotation, byteCount: MemoryLayout<Float>.size)
        let clearcoatRoughnessTransformOffsetScaleAddr = encoder.constantData(at: 84)
        clearcoatRoughnessTransformOffsetScaleAddr.copyMemory(from: clearcoatRoughnessTransformOffsetScale, byteCount: MemoryLayout<SIMD4<Float>>.size)
        let clearcoatRoughnessTransformRotationAddr = encoder.constantData(at: 85)
        clearcoatRoughnessTransformRotationAddr.copyMemory(from: clearcoatRoughnessTransformRotation, byteCount: MemoryLayout<Float>.size)
        let clearcoatNormalTransformOffsetScaleAddr = encoder.constantData(at: 86)
        clearcoatNormalTransformOffsetScaleAddr.copyMemory(from: clearcoatNormalTransformOffsetScale, byteCount: MemoryLayout<SIMD4<Float>>.size)
        let clearcoatNormalTransformRotationAddr = encoder.constantData(at: 87)
        clearcoatNormalTransformRotationAddr.copyMemory(from: clearcoatNormalTransformRotation, byteCount: MemoryLayout<Float>.size)
    }

    func makeFragmentArgumentEncoder() -> MTLArgumentEncoder {
        return fragmentFunction.makeArgumentEncoder(bufferIndex: PBRFragmentShaderArgsPtrBuffer.index)
    }

    func makeFragmentArgumentBuffer(
        encoder: MTLArgumentEncoder,
        argCount: Int
    ) throws -> MTLBuffer {
        guard let buffer = device.makeBuffer(length: encoder.encodedLength * argCount, options: [.storageModeShared]) else {
            throw SwiftGLTFError.makeRender(.argumentBufferCreateFailed, context: .capture(stage: .render))
        }
        return buffer
    }

    func makeScreenColorArgBuffer(
        sceneColor: MTLTexture,
        sceneColorSampler: MTLSamplerState
    ) -> MTLBuffer {
        let encoder = fragmentFunction.makeArgumentEncoder(bufferIndex: PBRFragmentShaderScreenColorBuffer.index)
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
        let encoder = fragmentFunction.makeArgumentEncoder(bufferIndex: PBRFragmentShaderScreenColorBuffer.index)
        let buffer = device.makeBuffer(length: encoder.encodedLength, options: .storageModeShared)!
        encoder.setArgumentBuffer(buffer, offset: 0)

        let flagAddr = encoder.constantData(at: 2)
        var useSceneColor: Bool = false
        flagAddr.copyMemory(from: &useSceneColor, byteCount: MemoryLayout<Bool>.size)
        return buffer
    }
}
