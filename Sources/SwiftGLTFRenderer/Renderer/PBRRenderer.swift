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
    private var envMapBundle: EnvMapBundle

    private let meshLoader: PBRMeshLoader
    private let pbrPipelineConnector: PBRPipelineConnector
    private let skyboxPipelineConnector: SkyboxPipelineConnector
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
    private var screenColorArgBuffer: MTLBuffer? = nil
    private let notUsedScreenColorArgBuffer: MTLBuffer
    private let sceneColorSampler: MTLSamplerState
    private var screenColorRPD: MTLRenderPassDescriptor? = nil
    private var transmissionRPD: MTLRenderPassDescriptor? = nil
    private var composeRPD: MTLRenderPassDescriptor? = nil
    private let composePipelineState: MTLRenderPipelineState

    // Indirect Command
    private var skyBoxIndirectCommandBuffer: MTLIndirectCommandBuffer?
    private let indirectSceneUniformsBuffer: MTLBuffer
    private let indirectCameraIndexBuffer: MTLBuffer
    private let indirectFreeCameraUniformsBuffer: MTLBuffer
    private let indirectModelMatrixBuffer: MTLBuffer
    private let indirectEnvMapArgumentBuffer: MTLBuffer

    private var needsTransmissionPass: Bool {
        bundle?.transmissionMeshes.count ?? 0 > 0
    }
    private var needsAnimationPass: Bool {
        bundle?.animations.count ?? 0 > 0
    }

    private var shouldUpdateIndirectEnvMapBuffer: Bool = true

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
        self.pbrPipelineConnector = try PBRPipelineConnector(
            device: device,
            library: library,
            config: pipelineStateConfig,
            shaderConnection: shaderConnection
        )
        self.meshLoader = PBRMeshLoader(
            device: device,
            shaderConnection: shaderConnection,
            pipelineConnector: pbrPipelineConnector
        )
        self.envMapLoader = EnvironmentMapLoader(
            device: device,
            library: library,
            shaderConnection: shaderConnection
        )

        self.defaultDSO = try makeLessEqualDepthStencilState(device: device)
        self.noWriteDSO = try makeLessEqualNoWriteDepthStencilState(device: device)

        // setup skybox
        let skyboxConfig = SkyboxPipelineConfig(
            sampleCount: sampleCount,
            colorPixelFormat: .rgba16Float,
            depthPixelFormat: .depth32Float
        )
        self.skyboxPipelineConnector = try SkyboxPipelineConnector(
            device: device,
            library: library,
            config: skyboxConfig
        )
        let skyboxLoader = try SkyboxMeshLoader(device: device)
        self.skyboxMesh = skyboxLoader.loadMesh()

        // setup default env map
        self.envMapBundle = try envMapLoader.makeEnvMapBundle(from: CGColor(gray: 0.0, alpha: 1.0))
        self.indirectEnvMapArgumentBuffer = device.makeBuffer(
            length: MemoryLayout<PBREnvMapArguments>.size,
            options: [.storageModePrivate]
        )!

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

        // ICB
        self.indirectSceneUniformsBuffer = device.makeBuffer(
            length: MemoryLayout<SceneUniforms>.size,
            options: .storageModeShared
        )!
        self.indirectModelMatrixBuffer = device.makeBuffer(
            length: MemoryLayout<simd_float4x4>.size,
            options: .storageModeShared
        )!
        self.indirectCameraIndexBuffer = device.makeBuffer(
            length: MemoryLayout<Int>.size,
            options: .storageModeShared
        )!
        self.indirectFreeCameraUniformsBuffer = device.makeBuffer(
            length: MemoryLayout<FreeCameraUniforms>.size,
            options: .storageModeShared
        )!

        // Dummy screen color arg buffer
        notUsedScreenColorArgBuffer = pbrPipelineConnector.makeScreenColorArgDummy()
    }

    // MARK: - Loading

    /// Load a gltf asset
    public func load(
        from asset: MDLAsset,
        sceneIndex: Int? = nil,
        animationIndex: Int? = nil,
        variantIndex: Int? = nil
    ) throws {
        let bundle = try meshLoader.loadMeshes(
            from: asset,
            sceneIndex: sceneIndex,
            animationIndex: animationIndex,
            variantIndex: variantIndex
        )
        self.bundle = bundle
        self.skyBoxIndirectCommandBuffer = buildSkyBoxIndirectCommandBuffer(
            skyboxMesh: skyboxMesh,
            bundle: bundle,
            fragmentArgumentsBuffer: indirectEnvMapArgumentBuffer
        )
    }

    /// Set environment from external URL (equirectangular .exr)
    public func setEnvironment(url: URL) throws {
        self.envMapBundle = try envMapLoader.makeEnvMapBundle(from: url)
        self.shouldUpdateIndirectEnvMapBuffer = true
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
        viewport: MTLViewport,
        fragmentParams: MTLBuffer,
        viewPos: SIMD3<Float>,
        cameraIndexBuffer: MTLBuffer,
        freeCameraUniformsBuffer: MTLBuffer,
        modelMatrixBuffer: MTLBuffer,
        showsSkybox: Bool = true,
        waitFence: MTLFence? = nil
    ) {
        guard let bundle else {
            os_log("No mesh loaded", type: .error)
            return
        }

        // Copy indirect buffers
        guard let skyBoxIndirectCommandBuffer else {
            os_log("Skybox indirect command buffer is not available", type: .error)
            return
        }
        guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
            os_log("Failed to create blit command encoder", type: .error)
            return
        }
        if shouldUpdateIndirectEnvMapBuffer {
            shouldUpdateIndirectEnvMapBuffer = false
            ensureIndirectEnvMapBuffer(
                blitEncoder: blitEncoder,
                fromEnvMapBuffer: envMapBundle.argBuffer,
                to: indirectEnvMapArgumentBuffer
            )
        }
        ensureIndirectBuffer(
            blitEncoder: blitEncoder,
            fromSceneUniformsBuffer: fragmentParams,
            fromModelMatrixBuffer: modelMatrixBuffer,
            fromCameraIndexBuffer: cameraIndexBuffer,
            fromFreeCameraUniformsBuffer: freeCameraUniformsBuffer
        )
        blitEncoder.endEncoding()

        // Ensure offscreen textures
        ensureOffscreenTargets(size: drawableSize)
        guard let screenColorTexture, let sceneTransmissionTexture, let screenColorRPD, let transmissionRPD, let screenPrefilterTexture else {
            os_log("Failed to create offscreen render targets", type: .error)
            return
        }

        // Pass 1: draw opaque + masked + blended to offscreen
        guard let screenColorRE = commandBuffer.makeRenderCommandEncoder(descriptor: screenColorRPD) else { return }
        screenColorRE.label = "[SwiftGLTF] PBR Screen Color Render Encoder"
        screenColorRE.setViewport(viewport)
        encodeScreenPass(
            renderEncoder: screenColorRE,
            bundle: bundle,
            fragmentParams: fragmentParams,
            viewPos: viewPos,
            cameraIndexBuffer: cameraIndexBuffer,
            freeCameraUniformsBuffer: freeCameraUniformsBuffer,
            modelMatrixBuffer: modelMatrixBuffer,
            showsSkybox: showsSkybox,
            skyBoxIndirectCommandBuffer: skyBoxIndirectCommandBuffer,
            waitFence: waitFence
        )

        if needsTransmissionPass {
            // Pass 2: Generate prefiltered scene texture
            shaderConnection.generatePrefilterSceneTexture(from: screenColorTexture, to: screenPrefilterTexture, commandBuffer: commandBuffer)
            
            // Pass 3: draw transmission to offscreen
            guard let transmissionRE = commandBuffer.makeRenderCommandEncoder(descriptor: transmissionRPD) else { return }
            transmissionRE.label = "[SwiftGLTF] PBR Transmission Render Encoder"
            transmissionRE.setViewport(viewport)
            encodeTransmissionPass(
                renderEncoder: transmissionRE,
                screenPrefilterTexture: screenPrefilterTexture,
                bundle: bundle,
                fragmentParams: fragmentParams,
                viewPos: viewPos,
                cameraIndexBuffer: cameraIndexBuffer,
                freeCameraUniformsBuffer: freeCameraUniformsBuffer,
                modelMatrixBuffer: modelMatrixBuffer
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
        fragmentParams: MTLBuffer,
        viewPos: SIMD3<Float>,
        cameraIndexBuffer: MTLBuffer,
        freeCameraUniformsBuffer: MTLBuffer,
        modelMatrixBuffer: MTLBuffer,
        showsSkybox: Bool,
        skyBoxIndirectCommandBuffer: MTLIndirectCommandBuffer,
        waitFence: MTLFence?
    ) {
        if let waitFence { renderEncoder.waitForFence(waitFence, before: .vertex) }

        if showsSkybox {
            drawSkybox(
                renderEncoder: renderEncoder,
                icb: skyBoxIndirectCommandBuffer,
                range: 0..<1,
                pso: skyboxPipelineConnector.pso,
                dso: skyboxPipelineConnector.dso,
                fragmentHeaps: [envMapBundle.heap],
            )
        }

        drawPBRScreen(
            renderEncoder: renderEncoder,
            opaquePSO: pbrPipelineConnector.opaquePSO,
            alphaBlendPSO: pbrPipelineConnector.alphaBlendPSO,
            defaultDSO: defaultDSO,
            noWriteDSO: noWriteDSO,
            vertexHeaps: bundle.vertexHeaps,
            fragmentHeaps: bundle.fragmentHeaps + [envMapBundle.heap],
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
            cameraIndexBuffer: cameraIndexBuffer,
            freeCameraUniformsBuffer: freeCameraUniformsBuffer,
            nodeCameraUniformsBuffer: bundle.nodeCameraUniformsBuffer,
            materialBuffer: bundle.materialBuffer,
            envMapArgBuffer: envMapBundle.argBuffer,
            fragmentParams: fragmentParams,
            modelMatrixBuffer: modelMatrixBuffer,
            screenColorArgsBuffer: notUsedScreenColorArgBuffer,
            viewPos: viewPos
        )
        renderEncoder.endEncoding()
    }

    private func encodeTransmissionPass(
        renderEncoder: MTLRenderCommandEncoder,
        screenPrefilterTexture: MTLTexture,
        bundle: PBRMeshBundle,
        fragmentParams: MTLBuffer,
        viewPos: SIMD3<Float>,
        cameraIndexBuffer: MTLBuffer,
        freeCameraUniformsBuffer: MTLBuffer,
        modelMatrixBuffer: MTLBuffer
    ) {
        guard let screenColorArgBuffer = self.screenColorArgBuffer else {
            os_log("screen color argument buffer is not available", type: .error)
            renderEncoder.endEncoding()
            return
        }
        renderEncoder.useResources([screenPrefilterTexture], usage: .read, stages: .fragment) // TODO: move to heap

        drawPBRTransmission(
            renderEncoder: renderEncoder,
            alphaBlendPSO: pbrPipelineConnector.alphaBlendPSO,
            defaultDSO: defaultDSO,
            vertexResources: bundle.vertexHeaps,
            fragmentResources: bundle.fragmentHeaps + [envMapBundle.heap],
            meshes: bundle.blendedMeshes + bundle.transmissionMeshes,
            worldTransformBuffer: bundle.worldTransformBuffer,
            boundingSpheresBuffer: bundle.boundingSpheresBuffer,
            jointsBuffer: bundle.jointsBuffer,
            inverseBindMatricesBuffer: bundle.inverseBindMatricesBuffer,
            morphWeightsBuffer: bundle.morphWeightsBuffer,
            morphDispatchesBuffer: bundle.morphDispatchesBuffer,
            cameraIndexBuffer: cameraIndexBuffer,
            freeCameraUniformsBuffer: freeCameraUniformsBuffer,
            nodeCameraUniformsBuffer: bundle.nodeCameraUniformsBuffer,
            materialBuffer: bundle.materialBuffer,
            envMapArgBuffer: envMapBundle.argBuffer,
            fragmentParams: fragmentParams,
            modelMatrixBuffer: modelMatrixBuffer,
            screenColorArgsBuffer: screenColorArgBuffer,
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
        if let screenPrefilterTexture = self.screenPrefilterTexture {
            self.screenColorArgBuffer = pbrPipelineConnector.makeScreenColorArgBuffer(
                sceneColor: screenPrefilterTexture,
                sceneColorSampler: sceneColorSampler
            )
        } else {
            self.screenColorArgBuffer = nil
        }
    }

    private func ensureIndirectBuffer(
        blitEncoder: MTLBlitCommandEncoder,
        fromSceneUniformsBuffer: MTLBuffer,
        fromModelMatrixBuffer: MTLBuffer,
        fromCameraIndexBuffer: MTLBuffer,
        fromFreeCameraUniformsBuffer: MTLBuffer
    ) {
        blitEncoder.copy(
            from: fromSceneUniformsBuffer,
            sourceOffset: 0,
            to: indirectSceneUniformsBuffer,
            destinationOffset: 0,
            size: MemoryLayout<SceneUniforms>.size
        )
        blitEncoder.copy(
            from: fromModelMatrixBuffer,
            sourceOffset: 0,
            to: indirectModelMatrixBuffer,
            destinationOffset: 0,
            size: MemoryLayout<simd_float4x4>.size
        )
        blitEncoder.copy(
            from: fromCameraIndexBuffer,
            sourceOffset: 0,
            to: indirectCameraIndexBuffer,
            destinationOffset: 0,
            size: MemoryLayout<Int>.size
        )
        blitEncoder.copy(
            from: fromFreeCameraUniformsBuffer,
            sourceOffset: 0,
            to: indirectFreeCameraUniformsBuffer,
            destinationOffset: 0,
            size: MemoryLayout<FreeCameraUniforms>.size
        )
    }

    private func ensureIndirectEnvMapBuffer(
        blitEncoder: MTLBlitCommandEncoder,
        fromEnvMapBuffer: MTLBuffer,
        to indirectEnvMapArgumentBuffer: MTLBuffer
    ) {
        blitEncoder.copy(
            from: fromEnvMapBuffer,
            sourceOffset: 0,
            to: indirectEnvMapArgumentBuffer,
            destinationOffset: 0,
            size: MemoryLayout<PBREnvMapArguments>.size
        )
    }

    // MARK: - ICB

    private func buildSkyBoxIndirectCommandBuffer(
        skyboxMesh: SkyboxMesh,
        bundle: PBRMeshBundle,
        fragmentArgumentsBuffer: MTLBuffer
    ) -> MTLIndirectCommandBuffer {
        let icbDesc = MTLIndirectCommandBufferDescriptor()
        icbDesc.commandTypes = .drawIndexed
        icbDesc.inheritBuffers = false
        icbDesc.maxVertexBufferBindCount = 5
        icbDesc.maxFragmentBufferBindCount = 1
        icbDesc.inheritPipelineState = true

        let icb = device.makeIndirectCommandBuffer(
            descriptor: icbDesc,
            maxCommandCount: 1,
            options: []
        )!

        icb.label = "[SwiftGLTF] Skybox Indirect Command Buffer"
        let cmd = icb.indirectRenderCommandAt(0)
        encodeDrawingSkybox(
            cmd: cmd,
            mesh: skyboxMesh,
            worldTransformBuffer: bundle.worldTransformBuffer,
            cameraIndexBuffer: indirectCameraIndexBuffer,
            freeCameraUniformsBuffer: indirectFreeCameraUniformsBuffer,
            nodeCameraUniformsBuffer: bundle.nodeCameraUniformsBuffer,
            fragmentArgumentsBuffer: fragmentArgumentsBuffer
        )
        return icb
    }
}
