import Img2Cubemap
import MetalKit
import os.log
import simd
import ModelIO
import SwiftGLTFParser
import SwiftGLTFCore
import SwiftGLTFShaderTypes

public class PBRRenderer {
    private let skyboxMesh: SkyboxMesh
    private let defaultEnvMapBundle: EnvMapBundle

    private let pbrPipelineConnector: PBRPipelineConnector
    private let skyboxPipelineConnector: SkyboxPipelineConnector
    private let envMapLoader: EnvironmentMapLoader
    private let shaderConnection: ShaderConnection

    private let writeDSO: MTLDepthStencilState
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
    private let screenColorArgumentBuffer: MTLBuffer
    private let noScreenColorArgumentBuffer: MTLBuffer
    private let sceneColorSampler: MTLSamplerState
    private var screenColorRPD: MTLRenderPassDescriptor? = nil
    private var transmissionRPD: MTLRenderPassDescriptor? = nil
    private var composeRPD: MTLRenderPassDescriptor? = nil
    private let composePipelineState: MTLRenderPipelineState

    // Indirect Command
    private var skyBoxIndirectCommandBuffer: MTLIndirectCommandBuffer?
    private var skyboxRenderPassContext: RenderPassContext?
    private var screenColorIndirectCommandBuffer: MTLIndirectCommandBuffer?
    private var screenColorRenderPassContext: RenderPassContext?
    private var transmissionIndirectCommandBuffer: MTLIndirectCommandBuffer?
    private var transmissionRenderPassContext: RenderPassContext?
    private let indirectHeap: MTLHeap
    private let indirectSceneUniformsBuffer: MTLBuffer
    private let indirectCameraIndexBuffer: MTLBuffer
    private let indirectFreeCameraUniformsBuffer: MTLBuffer
    private let indirectModelMatrixBuffer: MTLBuffer
    private let indirectEnvMapArgumentBuffer: MTLBuffer

    // FrameInFlight
    private let frameInFlightManager: PBRFrameInFlightManager

    public init(
        commandQueue: MTLCommandQueue,
        sampleCount: Int = 4,
        colorPixelFormat: MTLPixelFormat = .rgba8Unorm_srgb,
        depthPixelFormat: MTLPixelFormat = .depth32Float,
        shaderConnection: ShaderConnection,
        pbrPipelineConnector: PBRPipelineConnector,
        maxFramesInFlight: Int = 2
    ) throws {
        self.device = commandQueue.device
        self.commandQueue = commandQueue
        self.library = try device.makePackageLibrary()

        self.sampleCount = sampleCount
        self.colorPixelFormat = colorPixelFormat
        self.depthPixelFormat = depthPixelFormat
        self.shaderConnection = shaderConnection

        self.pbrPipelineConnector = pbrPipelineConnector
        self.envMapLoader = EnvironmentMapLoader(
            device: device,
            library: library,
            shaderConnection: shaderConnection
        )

        self.writeDSO = try makeLessEqualDepthStencilState(device: device)
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
        self.defaultEnvMapBundle = try envMapLoader.makeEnvMapBundle(from: CGColor(gray: 0.0, alpha: 1.0))
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
            throw SwiftGLTFError.render(description: "Failed to create sampler")
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
        self.indirectHeap = {
            let desc = MTLHeapDescriptor()
            desc.storageMode = .private
            desc.size =
            commandQueue.device.heapBufferSizeAndAlign(length:MemoryLayout<SceneUniforms>.size).alignedSize +
            commandQueue.device.heapBufferSizeAndAlign(length:MemoryLayout<simd_float4x4>.size).alignedSize +
            commandQueue.device.heapBufferSizeAndAlign(length:MemoryLayout<Int>.size).alignedSize +
            commandQueue.device.heapBufferSizeAndAlign(length:MemoryLayout<FreeCameraUniforms>.size).alignedSize
            let heap = commandQueue.device.makeHeap(descriptor: desc)!
            heap.label = "[SwiftGLTF] PBR Indirect Command Heap"
            return heap
        }()
        self.indirectSceneUniformsBuffer = indirectHeap.makeBuffer(
            length: MemoryLayout<SceneUniforms>.size,
            options: .storageModePrivate
        )!
        self.indirectModelMatrixBuffer = indirectHeap.makeBuffer(
            length: MemoryLayout<simd_float4x4>.size,
            options: .storageModePrivate
        )!
        self.indirectCameraIndexBuffer = indirectHeap.makeBuffer(
            length: MemoryLayout<Int>.size,
            options: .storageModePrivate
        )!
        self.indirectFreeCameraUniformsBuffer = indirectHeap.makeBuffer(
            length: MemoryLayout<FreeCameraUniforms>.size,
            options: .storageModePrivate
        )!

        // screen color arg buffer
        screenColorArgumentBuffer = device.makeBuffer(
            length: MemoryLayout<PBRScreenColorArguments>.size,
            options: [.storageModePrivate]
        )!
        noScreenColorArgumentBuffer = device.makeBuffer(
            length: MemoryLayout<PBRScreenColorArguments>.size,
            options: [.storageModePrivate]
        )!

        // FrameInFlight
        frameInFlightManager = PBRFrameInFlightManager(device: device, maxFramesInFlight: maxFramesInFlight)
    }

    // MARK: - Rendering

    public func render(
        commandBuffer: MTLCommandBuffer,
        context: FinalizedRenderingContext,
    ) {
        guard let meshBundle = context.meshBundle,
              let renderingState = context.renderingState else {
            os_log("PBRRenderer: Missing mesh bundle or rendering state in finalized rendering context", type: .error)
            return
        }

        let frameInFlightResources = frameInFlightManager.currentResourcesWith(
            modelMatrix: context.modelMatrix,
            sceneUniforms: context.sceneUniforms,
            cameraIndex: context.cameraIndex,
            freeCameraUniforms: context.freeCameraUniforms
        )

        var animationFence: MTLFence?
        if let animationState = context.animationState {
            animationFence = encodeAnimation(
                meshBundle: meshBundle,
                commandBuffer: commandBuffer,
                animationState: animationState
            )
        }

        encodeRenderingMesh(
            meshBundle: meshBundle,
            envMapBundle: context.envMapBundle,
            commandBuffer: commandBuffer,
            renderPassDescriptor: renderingState.renderPassDescriptor,
            drawableSize: renderingState.drawableSize,
            viewport: renderingState.viewport,
            fragmentParams: frameInFlightResources.sceneUniformsBuffer,
            cameraIndexBuffer: frameInFlightResources.cameraIndexBuffer,
            freeCameraUniformsBuffer: frameInFlightResources.freeCameraUniformsBuffer,
            modelMatrixBuffer: frameInFlightResources.modelMatrixBuffer,
            showsSkybox: context.showsSkybox,
            waitFence: animationFence
        )
    }

    private func encodeAnimation(
        meshBundle: PBRMeshBundle,
        commandBuffer cb: MTLCommandBuffer,
        animationState state: RendererAnimationState
    ) -> MTLFence? {
        guard meshBundle.needsAnimationPass else {
            // No animation to process
            return nil
        }
        guard let en = cb.makeComputeCommandEncoder() else {
            os_log("Failed to create compute command encoder", type: .error)
            return nil
        }
        en.label = "[SwiftGLTF] Animation Update Encoder"

        var localTransforms = meshBundle.nodeLevelHierarchy.localTransforms
        var morphWeights = meshBundle.originMorphWeights
        var morphDispatches = meshBundle.morphDispatches

        for animation in meshBundle.animations {
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

        let nlh = meshBundle.nodeLevelHierarchy.copy(localTransforms: localTransforms)
        do {
            try shaderConnection.computeWorldMatrices(
                nodeLevelHierarchy: nlh,
                out: meshBundle.worldTransformBuffer,
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

        meshBundle.morphWeightsBuffer.contents().copyMemory(
            from: &morphWeights,
            byteCount: MemoryLayout<Float>.size * morphWeights.count
        )
        meshBundle.morphDispatchesBuffer.contents().copyMemory(
            from: &morphDispatches,
            byteCount: MemoryLayout<MorphDispatch>.size * morphDispatches.count
        )

        return fence
    }

    // FIXME: prevMeshBundleID/prevEnvMapBundleID logic is a temporary hack to avoid rebuilding ICBs every frame.
    private var prevMeshBundleID: UUID?
    private var prevEnvMapBundleID: UUID?
    private func encodeRenderingMesh(
        meshBundle: PBRMeshBundle,
        envMapBundle: EnvMapBundle?,
        commandBuffer: MTLCommandBuffer,
        renderPassDescriptor: MTLRenderPassDescriptor,
        drawableSize: CGSize,
        viewport: MTLViewport,
        fragmentParams: MTLBuffer,
        cameraIndexBuffer: MTLBuffer,
        freeCameraUniformsBuffer: MTLBuffer,
        modelMatrixBuffer: MTLBuffer,
        showsSkybox: Bool,
        waitFence: MTLFence? = nil
    ) {
        // Pass 0: ensure buffers and textures
        // Copy indirect buffers
        guard let blitEncoder = commandBuffer.makeBlitCommandEncoder(),
              let blitFence = device.makeFence() else {
            os_log("Failed to create blit command encoder", type: .error)
            return
        }
        blitEncoder.label = "[SwiftGLTF] Ensure Indirect Buffers Blit Encoder"
        if prevMeshBundleID != meshBundle.id {
            defer { prevMeshBundleID = meshBundle.id }
            os_log("PBRRenderer: Rebuilding ICBs for new mesh bundle", type: .info)
            self.skyBoxIndirectCommandBuffer = buildSkyBoxIndirectCommandBuffer(
                skyboxMesh: skyboxMesh,
                bundle: meshBundle,
                fragmentArgumentsBuffer: indirectEnvMapArgumentBuffer
            )
            (self.screenColorIndirectCommandBuffer, self.screenColorRenderPassContext) = buildRenderScreenColorIndirectCommandBuffer(bundle: meshBundle)
            (self.transmissionIndirectCommandBuffer, self.transmissionRenderPassContext) = buildRenderTransmissionIndirectCommandBuffer(bundle: meshBundle)
        }
        guard let skyBoxIndirectCommandBuffer,
              let skyboxRenderPassContext,
              let screenColorIndirectCommandBuffer,
              let screenColorRenderPassContext else {
            os_log("Indirect command buffer is not available", type: .error)
            return
        }
        let envMapBundle = envMapBundle ?? defaultEnvMapBundle
        if prevEnvMapBundleID != envMapBundle.id {
            defer { prevEnvMapBundleID = envMapBundle.id }
            os_log("PBRRenderer: Updating indirect env map argument buffer for new env map bundle", type: .info)
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

        // Ensure offscreen textures
        ensureOffscreenTargets(blitEncoder: blitEncoder, size: drawableSize)
        blitEncoder.updateFence(blitFence)
        blitEncoder.endEncoding()
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
            skyBoxIndirectCommandBuffer: skyBoxIndirectCommandBuffer,
            skyboxRenderPassContext: skyboxRenderPassContext,
            pbrIndirectCommandBuffer: screenColorIndirectCommandBuffer,
            screenColorRenderPassContext: screenColorRenderPassContext,
            bundle: meshBundle,
            envMapBundle: envMapBundle,
            indirectHeap: indirectHeap,
            screenPrefilterTexture: screenPrefilterTexture,
            screenColorArgumentBuffer: screenColorArgumentBuffer,
            showsSkybox: showsSkybox,
            fences: [waitFence, blitFence].compactMap({$0})
        )

        if meshBundle.needsTransmissionPass {
            // Pass 2: Generate prefiltered scene texture
            shaderConnection.generatePrefilterSceneTexture(from: screenColorTexture, to: screenPrefilterTexture, commandBuffer: commandBuffer)
            
            // Pass 3: draw transmission to offscreen
            guard let transmissionRE = commandBuffer.makeRenderCommandEncoder(descriptor: transmissionRPD) else { return }
            guard let transmissionIndirectCommandBuffer,
                  let transmissionRenderPassContext else {
                os_log("Transmission indirect command buffer is not available", type: .error)
                return
            }
            transmissionRE.label = "[SwiftGLTF] PBR Transmission Render Encoder"
            transmissionRE.setViewport(viewport)
            encodeTransmissionPass(
                renderEncoder: transmissionRE,
                transmissionIndirectCommandBuffer: transmissionIndirectCommandBuffer,
                transmissionRenderPassContext: transmissionRenderPassContext,
                bundle: meshBundle,
                envMapBundle: envMapBundle,
                indirectHeap: indirectHeap,
                screenPrefilterTexture: screenPrefilterTexture,
                screenColorArgumentBuffer: screenColorArgumentBuffer
            )
        }

        // Pass 4: full-screen compose to screen
        guard let composeRE = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }
        composeRE.label = "[SwiftGLTF] PBR Compose Render Encoder"
        encodeComposePass(
            renderEncoder: composeRE,
            screenColorTexture: screenColorTexture,
            sceneTransmissionTexture: sceneTransmissionTexture,
            useTransmissionTexture: meshBundle.needsTransmissionPass ? 1 : 0
        )
    }

    // MARK: - Encoding passes

    private func encodeScreenPass(
        renderEncoder: MTLRenderCommandEncoder,
        skyBoxIndirectCommandBuffer: MTLIndirectCommandBuffer,
        skyboxRenderPassContext: RenderPassContext,
        pbrIndirectCommandBuffer: MTLIndirectCommandBuffer,
        screenColorRenderPassContext: RenderPassContext,
        bundle: PBRMeshBundle,
        envMapBundle: EnvMapBundle,
        indirectHeap: MTLHeap,
        screenPrefilterTexture: MTLTexture,
        screenColorArgumentBuffer: MTLBuffer,
        showsSkybox: Bool,
        fences: [MTLFence]
    ) {
        for fence in fences {
            renderEncoder.waitForFence(fence, before: .vertex)
        }

        renderEncoder.useResources(
            bundle.relationTableResources +
            [
                skyboxMesh.vertexBuffer,
                skyboxMesh.indexBuffer,
                screenPrefilterTexture,
                noScreenColorArgumentBuffer
            ],
            usage: .read,
            stages: [.vertex, .fragment]
        )
        renderEncoder.useHeaps(
            [indirectHeap, envMapBundle.heap] + bundle.heaps,
            stages: [.vertex, .fragment]
        )

        if showsSkybox {
            drawWithContext(
                renderEncoder: renderEncoder,
                icb: skyBoxIndirectCommandBuffer,
                context: skyboxRenderPassContext
            )
        }

        drawWithContext(
            renderEncoder: renderEncoder,
            icb: pbrIndirectCommandBuffer,
            context: screenColorRenderPassContext
        )
        renderEncoder.endEncoding()
    }

    private func encodeTransmissionPass(
        renderEncoder: MTLRenderCommandEncoder,
        transmissionIndirectCommandBuffer: MTLIndirectCommandBuffer,
        transmissionRenderPassContext: RenderPassContext,
        bundle: PBRMeshBundle,
        envMapBundle: EnvMapBundle,
        indirectHeap: MTLHeap,
        screenPrefilterTexture: MTLTexture,
        screenColorArgumentBuffer: MTLBuffer
    ) {
        renderEncoder.useResources(
            bundle.relationTableResources +
            [screenPrefilterTexture, screenColorArgumentBuffer],
            usage: .read,
            stages: [.vertex, .fragment]
        )
        renderEncoder.useHeaps(
            [indirectHeap, envMapBundle.heap] + bundle.heaps,
            stages: [.vertex, .fragment]
        )

        drawWithContext(
            renderEncoder: renderEncoder,
            icb: transmissionIndirectCommandBuffer,
            context: transmissionRenderPassContext
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

    private func ensureOffscreenTargets(
        blitEncoder: MTLBlitCommandEncoder,
        size: CGSize
    ) {
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
        self.screenPrefilterTexture = device.makeTexture(descriptor: prefilDesc)!
        let sourceScreenColorArgumentBuffer = pbrPipelineConnector.makeScreenColorArgBuffer(
            sceneColor: screenPrefilterTexture!,
            sceneColorSampler: sceneColorSampler
        )
        blitEncoder.copy(
            from: sourceScreenColorArgumentBuffer,
            sourceOffset: 0,
            to: self.screenColorArgumentBuffer,
            destinationOffset: 0,
            size: MemoryLayout<PBRScreenColorArguments>.size
        )

        let sourceNoScreenColorArgumentBuffer = pbrPipelineConnector.makeScreenColorArgDummy()
        blitEncoder.copy(
            from: sourceNoScreenColorArgumentBuffer,
            sourceOffset: 0,
            to: self.noScreenColorArgumentBuffer,
            destinationOffset: 0,
            size: MemoryLayout<PBRScreenColorArguments>.size
        )
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
        self.skyboxRenderPassContext = encodeDrawingSkybox(
            icb: icb,
            mesh: skyboxMesh,
            pso: skyboxPipelineConnector.pso,
            dso: skyboxPipelineConnector.dso,
            worldTransformBuffer: bundle.worldTransformBuffer,
            cameraIndexBuffer: indirectCameraIndexBuffer,
            freeCameraUniformsBuffer: indirectFreeCameraUniformsBuffer,
            nodeCameraUniformsBuffer: bundle.nodeCameraUniformsBuffer,
            fragmentArgumentsBuffer: fragmentArgumentsBuffer
        )
        return icb
    }

    private func buildRenderScreenColorIndirectCommandBuffer(bundle: PBRMeshBundle) -> (MTLIndirectCommandBuffer, RenderPassContext) {
        let icbDesc = MTLIndirectCommandBufferDescriptor()
        icbDesc.commandTypes = .drawIndexed
        icbDesc.inheritBuffers = false
        icbDesc.inheritPipelineState = true
        icbDesc.maxVertexBufferBindCount = Int(PBRVertexShaderBufferCount.rawValue)
        icbDesc.maxFragmentBufferBindCount = Int(PBRFragmentShaderBufferCount.rawValue)

        let icb = device.makeIndirectCommandBuffer(
            descriptor: icbDesc,
            maxCommandCount: computePBRScreenDrawingCount(meshes: bundle.meshes),
            options: [.storageModeShared]
        )!
        icb.label = "[SwiftGLTF] PBR Indirect Command Buffer"

        let renderContext = encodeDrawingPBRScreen(
            icb: icb,
            meshes: bundle.meshes,
            opaquePSO: pbrPipelineConnector.opaquePSO,
            alphaBlendPSO: pbrPipelineConnector.alphaBlendPSO,
            writeDSO: writeDSO,
            worldTransformBuffer: bundle.worldTransformBuffer,
            boundingSpheresBuffer: bundle.boundingSpheresBuffer,
            jointsBuffer: bundle.jointsBuffer,
            inverseBindMatricesBuffer: bundle.inverseBindMatricesBuffer,
            morphWeightsBuffer: bundle.morphWeightsBuffer,
            morphDispatchesBuffer: bundle.morphDispatchesBuffer,
            cameraIndexBuffer: indirectCameraIndexBuffer,
            freeCameraUniformsBuffer: indirectFreeCameraUniformsBuffer,
            nodeCameraUniformsBuffer: bundle.nodeCameraUniformsBuffer,
            materialBuffer: bundle.materialBuffer,
            envMapArgBuffer: indirectEnvMapArgumentBuffer,
            fragmentParams: indirectSceneUniformsBuffer,
            modelMatrixBuffer: indirectModelMatrixBuffer,
            screenColorArgsBuffer: noScreenColorArgumentBuffer
        )

        return (icb, renderContext)
    }

    private func buildRenderTransmissionIndirectCommandBuffer(bundle: PBRMeshBundle) -> (MTLIndirectCommandBuffer, RenderPassContext) {
        let icbDesc = MTLIndirectCommandBufferDescriptor()
        icbDesc.commandTypes = .drawIndexed
        icbDesc.inheritBuffers = false
        icbDesc.inheritPipelineState = true
        icbDesc.maxVertexBufferBindCount = Int(PBRVertexShaderBufferCount.rawValue)
        icbDesc.maxFragmentBufferBindCount = Int(PBRFragmentShaderBufferCount.rawValue)

        let icb = device.makeIndirectCommandBuffer(
            descriptor: icbDesc,
            maxCommandCount: computeTransmissionDrawingCount(meshes: bundle.meshes),
            options: [.storageModeShared]
        )!
        icb.label = "[SwiftGLTF] PBR Indirect Command Buffer"

        let renderContext = encodeDrawingTransmission(
            icb: icb,
            meshes: bundle.meshes,
            alphaBlendPSO: pbrPipelineConnector.alphaBlendPSO,
            writeDSO: writeDSO,
            worldTransformBuffer: bundle.worldTransformBuffer,
            boundingSpheresBuffer: bundle.boundingSpheresBuffer,
            jointsBuffer: bundle.jointsBuffer,
            inverseBindMatricesBuffer: bundle.inverseBindMatricesBuffer,
            morphWeightsBuffer: bundle.morphWeightsBuffer,
            morphDispatchesBuffer: bundle.morphDispatchesBuffer,
            cameraIndexBuffer: indirectCameraIndexBuffer,
            freeCameraUniformsBuffer: indirectFreeCameraUniformsBuffer,
            nodeCameraUniformsBuffer: bundle.nodeCameraUniformsBuffer,
            materialBuffer: bundle.materialBuffer,
            envMapArgBuffer: indirectEnvMapArgumentBuffer,
            fragmentParams: indirectSceneUniformsBuffer,
            modelMatrixBuffer: indirectModelMatrixBuffer,
            screenColorArgsBuffer: screenColorArgumentBuffer
        )

        return (icb, renderContext)
    }
}
