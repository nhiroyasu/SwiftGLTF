import Img2Cubemap
import MetalKit
import os.log
import simd
import ModelIO
import SwiftGLTFParser
import SwiftGLTFCore
import SwiftGLTFShaderTypes

public class PBRRenderer {
    private var bundle: PBRMeshBundle? = nil

    private var skyboxMesh: SkyboxMesh
    private var envMapArgBuffer: MTLBuffer
    private var envMapHeap: MTLHeap
    // Variables to prevent deallocation by ARC
    private var _prefilterEnvMap: MTLTexture
    private var _irradianceMap: MTLTexture
    private var _brdfLUT: MTLTexture
    private var _prefilterSheenMap: MTLTexture

    private let meshLoader: PBRMeshLoader
    private let pipelineConnector: PBRPipelineConnector
    private let envMapLoader: EnvironmentMapLoader
    private let shaderConnection: ShaderConnection

    private let defaultDSO: MTLDepthStencilState
    private let noWriteDSO: MTLDepthStencilState

    private let device: MTLDevice
    private let library: MTLLibrary
    private let commandQueue: MTLCommandQueue

    private let sampleCount: Int
    private let colorPixelFormat: MTLPixelFormat
    private let depthPixelFormat: MTLPixelFormat

    // Offscreen targets
    private var screenColorMSAATexture: MTLTexture? = nil // offscreen color (opaque + mask + blend)
    private var screenColorTexture: MTLTexture? = nil
    private var sceneTransmissionMSAATexture: MTLTexture? = nil // transmission only
    private var sceneTransmissionTexture: MTLTexture? = nil
    private var screenPrefilterTexture: MTLTexture? = nil // mip-chain prefiltered scene for rough transmission
    private var sceneDepthMSAATexture: MTLTexture? = nil
    private let sceneColorSampler: MTLSamplerState
    private var screenColorRPD: MTLRenderPassDescriptor? = nil
    private var transmissionRPD: MTLRenderPassDescriptor? = nil
    private var composeRPD: MTLRenderPassDescriptor? = nil
    private let composePipelineState: MTLRenderPipelineState

    private var needsTransmissionPass: Bool {
        bundle?.transmissionMeshes.count ?? 0 > 0
    }
    private var needsAnimationPass: Bool {
        bundle?.animations.count ?? 0 > 0
    }

    public init(
        commandQueue: MTLCommandQueue,
        sampleCount: Int = 4,
        colorPixelFormat: MTLPixelFormat = .rgba8Unorm_srgb,
        depthPixelFormat: MTLPixelFormat = .depth32Float
    ) throws {
        self.device = commandQueue.device
        self.commandQueue = commandQueue
        self.library = try device.makePackageLibrary()

        self.sampleCount = sampleCount
        self.colorPixelFormat = colorPixelFormat
        self.depthPixelFormat = depthPixelFormat
        self.shaderConnection = ShaderConnection(
            device: device,
            library: library,
            commandQueue: commandQueue
        )

        let pipelineStateConfig = PipelineStateLoaderConfig(
            sampleCount: sampleCount,
            colorPixelFormat: .rgba16Float,
            depthPixelFormat: .depth32Float
        )
        self.pipelineConnector = try PBRPipelineConnector(
            device: device,
            library: library,
            config: pipelineStateConfig,
            shaderConnection: shaderConnection
        )
        self.meshLoader = PBRMeshLoader(
            device: device,
            shaderConnection: shaderConnection,
            pipelineConnector: pipelineConnector
        )
        self.envMapLoader = EnvironmentMapLoader(
            device: device,
            library: library,
            shaderConnection: shaderConnection
        )

        self.defaultDSO = try makeLessEqualDepthStencilState(device: device)
        self.noWriteDSO = try makeLessEqualNoWriteDepthStencilState(device: device)

        let skyboxConfig = SkyboxPipelineConfig(
            sampleCount: sampleCount,
            colorPixelFormat: .rgba16Float,
            depthPixelFormat: .depth32Float
        )
        let skyboxLoader = try SkyboxMeshLoader(
            device: device,
            library: library,
            config: skyboxConfig
        )
        self.skyboxMesh = skyboxLoader.loadMesh()

        (
            self.envMapHeap,
            self._prefilterEnvMap,
            self._irradianceMap,
            self._brdfLUT,
            self._prefilterSheenMap
        ) = try envMapLoader.makeEnvMapHeapAndTexture(from: CGColor(gray: 0.0, alpha: 1.0))
        self.envMapArgBuffer = try pipelineConnector.makeEnvMapArgBuffer(
            prefilterEnvMap: _prefilterEnvMap,
            irradianceMap: _irradianceMap,
            brdfLUT: _brdfLUT,
            prefilterSheenMap: _prefilterSheenMap
        )

        // Scene color sampler
        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.mipFilter = .nearest
        samplerDesc.sAddressMode = .clampToEdge
        samplerDesc.tAddressMode = .clampToEdge
        samplerDesc.supportArgumentBuffers = true
        guard let screenColorSampler = device.makeSamplerState(descriptor: samplerDesc) else {
            throw SwiftGLTFError.makeRender(.samplerCreateFailed, context: .capture(stage: .render))
        }
        self.sceneColorSampler = screenColorSampler

        // Compose pipeline (full-screen quad)
        let vFun = library.makeFunction(name: "fullscreen_vertex")!
        let fFun = library.makeFunction(name: "compose_fragment")!
        let composeDesc = MTLRenderPipelineDescriptor()
        composeDesc.vertexFunction = vFun
        composeDesc.fragmentFunction = fFun
        composeDesc.colorAttachments[0].pixelFormat = colorPixelFormat
        composeDesc.depthAttachmentPixelFormat = depthPixelFormat
        composeDesc.rasterSampleCount = sampleCount
        self.composePipelineState = try device.makeRenderPipelineState(descriptor: composeDesc)
    }

    // MARK: - Rendering

    public func animation(
        commandBuffer cb: MTLCommandBuffer,
        animationState state: RendererAnimationState
    ) -> MTLFence? {
        guard let bundle else {
            os_log("No mesh loaded", type: .error)
            return nil
        }
        guard needsAnimationPass else {
            // No animation to process
            return nil
        }
        guard let en = cb.makeComputeCommandEncoder() else {
            os_log("Failed to create compute command encoder", type: .error)
            return nil
        }
        en.label = "[SwiftGLTF] Animation Update Encoder"

        var localTransforms = bundle.nodeLevelHierarchy.localTransforms
        var morphWeights = bundle.originMorphWeights
        var morphDispatches = bundle.morphDispatches

        for animation in bundle.animations {
            let trs = evaluateTRS(
                type: animation.type,
                interpolation: animation.interpolation,
                keyFrameTimes: animation.keyframes,
                duration: animation.duration,
                time: state.time,
                looping: state.isLooping
            )
            let weights = evaluateWeights(
                type: animation.type,
                interpolation: animation.interpolation,
                keyFrameTimes: animation.keyframes,
                duration: animation.duration,
                time: state.time,
                looping: state.isLooping
            )

            let target = animation.targetNode

            localTransforms[target] = trs.apply(localTransforms[target])

            let dispatch = morphDispatches[target]
            if dispatch.length == 0 {
                morphWeights.insert(contentsOf: weights, at: Int(dispatch.offset))
                morphDispatches[target] = MorphDispatch(
                    offset: dispatch.offset,
                    length: Int64(weights.count)
                )
            } else {
                morphWeights.replaceSubrange(Int(dispatch.offset)..<Int(dispatch.offset + dispatch.length), with: weights)
            }
        }

        let nlh = bundle.nodeLevelHierarchy.copy(localTransforms: localTransforms)
        do {
            try shaderConnection.computeWorldMatrices(
                nodeLevelHierarchy: nlh,
                out: bundle.worldTransformBuffer,
                commandEncoder: en
            )
        } catch {
            os_log("Failed to compute world matrices: %@", type: .error, String(describing: error))
            return nil
        }

        guard let fence = device.makeFence() else {
            os_log("Failed to create fence", type: .error)
            return nil
        }
        en.updateFence(fence)

        bundle.morphWeightsBuffer.contents().copyMemory(
            from: &morphWeights,
            byteCount: MemoryLayout<Float>.size * morphWeights.count
        )
        bundle.morphDispatchesBuffer.contents().copyMemory(
            from: &morphDispatches,
            byteCount: MemoryLayout<MorphDispatch>.size * morphDispatches.count
        )

        return fence
    }

    public func render(
        commandBuffer: MTLCommandBuffer,
        renderPassDescriptor: MTLRenderPassDescriptor,
        drawableSize: CGSize,
        mvpUniformBuffer: MTLBuffer,
        fragmentParams: MTLBuffer,
        viewPos: SIMD3<Float>,
        showsSkybox: Bool = true,
        waitFence: MTLFence? = nil
    ) {
        guard let bundle else {
            os_log("No mesh loaded", type: .error)
            return
        }

        // Ensure offscreen textures
        ensureOffscreenTargets(size: drawableSize)
        guard let screenColorTexture, let sceneTransmissionTexture, let screenColorRPD, let transmissionRPD, let screenPrefilterTexture else {
            os_log("Failed to create offscreen render targets", type: .error)
            return
        }

        // Pass 1: draw opaque + masked + blended to offscreen
        guard let screenColorRE = commandBuffer.makeRenderCommandEncoder(descriptor: screenColorRPD) else { return }
        screenColorRE.label = "[SwiftGLTF] PBR Screen Color Render Encoder"
        encodeScreenPass(
            renderEncoder: screenColorRE,
            bundle: bundle,
            mvpUniformBuffer: mvpUniformBuffer,
            fragmentParams: fragmentParams,
            viewPos: viewPos,
            showsSkybox: showsSkybox,
            waitFence: waitFence
        )

        if needsTransmissionPass {
            // Pass 2: Generate prefiltered scene texture
            shaderConnection.generatePrefilterSceneTexture(from: screenColorTexture, to: screenPrefilterTexture, commandBuffer: commandBuffer)
            
            // Pass 3: draw transmission to offscreen
            guard let transmissionRE = commandBuffer.makeRenderCommandEncoder(descriptor: transmissionRPD) else { return }
            transmissionRE.label = "[SwiftGLTF] PBR Transmission Render Encoder"
            encodeTransmissionPass(
                renderEncoder: transmissionRE,
                screenPrefilterTexture: screenPrefilterTexture,
                bundle: bundle,
                mvpUniformBuffer: mvpUniformBuffer,
                fragmentParams: fragmentParams,
                viewPos: viewPos
            )
        }

        // Pass 4: full-screen compose to screen
        guard let composeRE = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }
        composeRE.label = "[SwiftGLTF] PBR Compose Render Encoder"
        encodeComposePass(
            renderEncoder: composeRE,
            screenColorTexture: screenColorTexture,
            sceneTransmissionTexture: sceneTransmissionTexture,
            useTransmissionTexture: needsTransmissionPass ? 1 : 0
        )
    }

    // MARK: - Encoding passes

    private func encodeScreenPass(
        renderEncoder: MTLRenderCommandEncoder,
        bundle: PBRMeshBundle,
        mvpUniformBuffer: MTLBuffer,
        fragmentParams: MTLBuffer,
        viewPos: SIMD3<Float>,
        showsSkybox: Bool,
        waitFence: MTLFence?
    ) {
        if let waitFence { renderEncoder.waitForFence(waitFence, before: .vertex) }

        if showsSkybox {
            drawSkybox(
                renderEncoder: renderEncoder,
                mesh: skyboxMesh,
                mvpUniformBuffer: mvpUniformBuffer,
                specularCubeMapTexture: _prefilterEnvMap
            )
        }

        drawPBRScreen(
            renderEncoder: renderEncoder,
            opaquePSO: pipelineConnector.opaquePSO,
            alphaBlendPSO: pipelineConnector.alphaBlendPSO,
            defaultDSO: defaultDSO,
            noWriteDSO: noWriteDSO,
            vertexResources: bundle.vertexResources,
            vertexHeaps: bundle.vertexHeaps,
            fragmentHeaps: bundle.fragmentHeaps + [envMapHeap],
            opaqueMeshes: bundle.opaqueMeshes,
            maskedMeshes: bundle.maskedMeshes,
            blendedMeshes: bundle.blendedMeshes,
            transmissionMeshes: bundle.transmissionMeshes,
            worldTransformBuffer: bundle.worldTransformBuffer,
            boundingSpheresBuffer: bundle.boundingSpheresBuffer,
            jointsBuffer: bundle.jointsBuffer,
            inverseBindMatricesBuffer: bundle.inverseBindMatricesBuffer,
            morphWeightsBuffer: bundle.morphWeightsBuffer,
            morphDispatchesBuffer: bundle.morphDispatchesBuffer,
            envMapArgBuffer: envMapArgBuffer,
            fragmentParams: fragmentParams,
            mvpUniformBuffer: mvpUniformBuffer,
            screenColorArgsBuffer: pipelineConnector.makeScreenColorArgDummy(),
            viewPos: viewPos
        )
        renderEncoder.endEncoding()
    }

    private func encodeTransmissionPass(
        renderEncoder: MTLRenderCommandEncoder,
        screenPrefilterTexture: MTLTexture,
        bundle: PBRMeshBundle,
        mvpUniformBuffer: MTLBuffer,
        fragmentParams: MTLBuffer,
        viewPos: SIMD3<Float>
    ) {
        let sceneColorArgBuffer = pipelineConnector.makeScreenColorArgBuffer(
            sceneColor: screenPrefilterTexture,
            sceneColorSampler: sceneColorSampler
        )
        renderEncoder.useResources([screenPrefilterTexture], usage: .read, stages: .fragment) // TODO: move to heap

        drawPBRTransmission(
            renderEncoder: renderEncoder,
            alphaBlendPSO: pipelineConnector.alphaBlendPSO,
            defaultDSO: defaultDSO,
            vertexResources: bundle.vertexHeaps,
            fragmentResources: bundle.fragmentHeaps + [envMapHeap],
            meshes: bundle.blendedMeshes + bundle.transmissionMeshes,
            worldTransformBuffer: bundle.worldTransformBuffer,
            boundingSpheresBuffer: bundle.boundingSpheresBuffer,
            jointsBuffer: bundle.jointsBuffer,
            inverseBindMatricesBuffer: bundle.inverseBindMatricesBuffer,
            morphWeightsBuffer: bundle.morphWeightsBuffer,
            morphDispatchesBuffer: bundle.morphDispatchesBuffer,
            envMapArgBuffer: envMapArgBuffer,
            fragmentParams: fragmentParams,
            mvpUniformBuffer: mvpUniformBuffer,
            screenColorArgsBuffer: sceneColorArgBuffer,
            viewPos: viewPos
        )
        renderEncoder.endEncoding()
    }

    private func encodeComposePass(
        renderEncoder: MTLRenderCommandEncoder,
        screenColorTexture: MTLTexture,
        sceneTransmissionTexture: MTLTexture,
        useTransmissionTexture: UInt32
    ) {
        renderEncoder.setRenderPipelineState(composePipelineState)
        renderEncoder.setFragmentTexture(screenColorTexture, index: 0)
        renderEncoder.setFragmentTexture(sceneTransmissionTexture, index: 1)

        var useTransTex: UInt32 = useTransmissionTexture
        renderEncoder.setFragmentBytes(&useTransTex, length: MemoryLayout<UInt32>.size, index: 0)
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        renderEncoder.endEncoding()
    }

    private func ensureOffscreenTargets(size: CGSize) {
        let width = max(Int(size.width), 1)
        let height = max(Int(size.height), 1)
        if screenColorMSAATexture?.width == width && screenColorMSAATexture?.height == height { return } // already correct size

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
        screenColorMSAATexture = device.makeTexture(descriptor: msaaDesc)
        sceneTransmissionMSAATexture = device.makeTexture(descriptor: msaaDesc)

        let resolveDesc = msaaDesc.copy() as! MTLTextureDescriptor
        resolveDesc.textureType = .type2D
        resolveDesc.sampleCount = 1
        screenColorTexture = device.makeTexture(descriptor: resolveDesc)
        sceneTransmissionTexture = device.makeTexture(descriptor: resolveDesc)

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
        sceneDepthMSAATexture = device.makeTexture(descriptor: depthMSAADesc)

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
        self.screenColorRPD = scPRD

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
        self.transmissionRPD = transRPD

        // Create destination mipmapped texture
        let prefilDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: width,
            height: height,
            mipmapped: true
        )
        prefilDesc.usage = [.shaderRead, .shaderWrite]
        prefilDesc.storageMode = .shared
        self.screenPrefilterTexture = device.makeTexture(descriptor: prefilDesc)
    }

    // MARK: - Update states

    /// Load a gltf asset
    public func load(from asset: MDLAsset, sceneIndex: Int? = nil) async throws {
        self.bundle = try await meshLoader.loadMeshes(from: asset, sceneIndex: sceneIndex)
    }

    /// Set environment from external URL (equirectangular .exr)
    public func setEnvironment(url: URL) async throws {
        (
            self.envMapHeap,
            self._prefilterEnvMap,
            self._irradianceMap,
            self._brdfLUT,
            self._prefilterSheenMap
        ) = try envMapLoader.makeEnvMapHeapAndTexture(url: url)
        self.envMapArgBuffer = try pipelineConnector.makeEnvMapArgBuffer(
            prefilterEnvMap: _prefilterEnvMap,
            irradianceMap: _irradianceMap,
            brdfLUT: _brdfLUT,
            prefilterSheenMap: _prefilterSheenMap
        )
    }

    /// Set environment from existing cube texture
    public func setEnvironment(cubeTexture: MTLTexture) throws {
        (
            self.envMapHeap,
            self._prefilterEnvMap,
            self._irradianceMap,
            self._brdfLUT,
            self._prefilterSheenMap
        ) = try envMapLoader.makeEnvMapHeapAndTexture(fromCube: cubeTexture)
        self.envMapArgBuffer = try pipelineConnector.makeEnvMapArgBuffer(
            prefilterEnvMap: _prefilterEnvMap,
            irradianceMap: _irradianceMap,
            brdfLUT: _brdfLUT,
            prefilterSheenMap: _prefilterSheenMap
        )
    }
}
