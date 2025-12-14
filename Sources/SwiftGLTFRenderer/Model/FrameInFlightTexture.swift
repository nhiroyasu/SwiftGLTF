import Metal
import SwiftGLTFCore
import SwiftGLTFShaderTypes

struct PBROffscreenTextureResources {
    let screenColorMSAATexture: MTLTexture // offscreen color (opaque + mask + blend)
    let screenColorTexture: MTLTexture
    let sceneTransmissionMSAATexture: MTLTexture // transmission only
    let sceneTransmissionTexture: MTLTexture
    let screenPrefilterTexture: MTLTexture // mip-chain prefiltered scene for rough transmission
    let sceneDepthMSAATexture: MTLTexture
    let sceneColorSampler: MTLSamplerState
    let screenColorRPD: MTLRenderPassDescriptor
    let transmissionRPD: MTLRenderPassDescriptor
}

class PBROffscreenTextureManager {
    private let device: MTLDevice
    private let sampleCount: Int
    private let maxFramesInFlight: Int
    private let framesInFlightSemaphore: DispatchSemaphore

    private var currentFrameIndex: Int = 0
    private let stateSemaphore = DispatchSemaphore(value: 1)

    private var cache: [(size: CGSize, resources: PBROffscreenTextureResources?)]

    init(device: MTLDevice, sampleCount: Int, maxFramesInFlight: Int) {
        self.device = device
        self.sampleCount = sampleCount
        self.maxFramesInFlight = maxFramesInFlight
        self.framesInFlightSemaphore = DispatchSemaphore(value: maxFramesInFlight)
        self.cache = Array(repeating: (CGSize.zero, nil), count: maxFramesInFlight)
    }

    private func _updateFrameWithSave(_ size: CGSize, _ resources: PBROffscreenTextureResources) {
        stateSemaphore.wait()
        currentFrameIndex = (currentFrameIndex + 1) % maxFramesInFlight
        cache[currentFrameIndex] = (size, resources)
        stateSemaphore.signal()
    }

    func resolve(for size: CGSize) throws -> PBROffscreenTextureResources {
        framesInFlightSemaphore.wait()
        defer { framesInFlightSemaphore.signal() }

        // Check cache
        if cache[currentFrameIndex].size == size {
            if let r = cache[currentFrameIndex].resources {
                _updateFrameWithSave(size, r)
                return r
            } else {
                throw SwiftGLTFError.render(description: "Cached resources missing")
            }
        }

        let width = max(Int(size.width), 1)
        let height = max(Int(size.height), 1)

        let msaaDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: width,
            height: height,
            mipmapped: false
        )
        msaaDesc.usage = [.renderTarget, .shaderRead]
        msaaDesc.storageMode = .private
        msaaDesc.textureType = .type2DMultisample
        msaaDesc.sampleCount = sampleCount
        let screenColorMSAATexture = device.makeTexture(descriptor: msaaDesc)
        let sceneTransmissionMSAATexture = device.makeTexture(descriptor: msaaDesc)

        let resolveDesc = msaaDesc.copy() as! MTLTextureDescriptor
        resolveDesc.textureType = .type2D
        resolveDesc.sampleCount = 1
        let screenColorTexture = device.makeTexture(descriptor: resolveDesc)
        let sceneTransmissionTexture = device.makeTexture(descriptor: resolveDesc)

        let depthMSAADesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float,
            width: width,
            height: height,
            mipmapped: false
        )
        depthMSAADesc.usage = [.renderTarget]
        depthMSAADesc.storageMode = .private
        depthMSAADesc.textureType = .type2DMultisample
        depthMSAADesc.sampleCount = sampleCount
        let sceneDepthMSAATexture = device.makeTexture(descriptor: depthMSAADesc)

        let scPRD = MTLRenderPassDescriptor()
        let scColorAtt = scPRD.colorAttachments[0]!
        scColorAtt.texture = screenColorMSAATexture
        scColorAtt.resolveTexture = screenColorTexture
        scColorAtt.loadAction = .clear
        scColorAtt.storeAction = .multisampleResolve
        scColorAtt.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        scPRD.depthAttachment.texture = sceneDepthMSAATexture
        scPRD.depthAttachment.loadAction = .clear
        scPRD.depthAttachment.clearDepth = 1.0
        scPRD.depthAttachment.storeAction = .store
        let screenColorRPD = scPRD

        let transRPD = MTLRenderPassDescriptor()
        let transColorAttr = transRPD.colorAttachments[0]!
        transColorAttr.texture = sceneTransmissionMSAATexture
        transColorAttr.resolveTexture = sceneTransmissionTexture
        transColorAttr.loadAction = .clear
        transColorAttr.clearColor = MTLClearColorMake(0, 0, 0, 0)
        transColorAttr.storeAction = .multisampleResolve
        transRPD.depthAttachment.texture = sceneDepthMSAATexture
        transRPD.depthAttachment.loadAction = .load
        transRPD.depthAttachment.storeAction = .store
        let transmissionRPD = transRPD

        // Scene color sampler
        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.mipFilter = .nearest
        samplerDesc.sAddressMode = .clampToEdge
        samplerDesc.tAddressMode = .clampToEdge
        samplerDesc.supportArgumentBuffers = true
        guard let screenColorSampler = device.makeSamplerState(descriptor: samplerDesc) else {
            throw SwiftGLTFError.render(description: "Failed to create screen color sampler")
        }

        // Create destination mipmapped texture
        let prefilDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: width,
            height: height,
            mipmapped: true
        )
        prefilDesc.usage = [.shaderRead, .shaderWrite]
        prefilDesc.storageMode = .shared
        let screenPrefilterTexture = device.makeTexture(descriptor: prefilDesc)

        guard let screenColorMSAATexture,
              let screenColorTexture,
              let sceneTransmissionMSAATexture,
              let sceneTransmissionTexture,
              let screenPrefilterTexture,
              let sceneDepthMSAATexture else {
            throw SwiftGLTFError.render(description: "Failed to create offscreen textures")
        }
        let resources = PBROffscreenTextureResources(
            screenColorMSAATexture: screenColorMSAATexture,
            screenColorTexture: screenColorTexture,
            sceneTransmissionMSAATexture: sceneTransmissionMSAATexture,
            sceneTransmissionTexture: sceneTransmissionTexture,
            screenPrefilterTexture: screenPrefilterTexture,
            sceneDepthMSAATexture: sceneDepthMSAATexture,
            sceneColorSampler: screenColorSampler,
            screenColorRPD: screenColorRPD,
            transmissionRPD: transmissionRPD
        )

        _updateFrameWithSave(size, resources)
        return resources
    }
}
