import Img2Cubemap
import MetalKit
import OSLog
import simd
import ModelIO
import SwiftGLTFParser
import SwiftGLTFCore
import SwiftGLTFShaderTypes

public class PBRRenderer {
    private let defaultEnvMapBundle: EnvMapBundle

    private let pbrPipelineConnector: PBRPipelineConnector
    private let envMapLoader: EnvironmentMapLoader
    private let shaderConnection: ShaderConnection
    private let offscreenTextureManager: PBROffscreenTextureManager
    private let prefilterSceneGenerator: PrefilterSceneGenerator

    private let writeDSO: MTLDepthStencilState
    private let noWriteDSO: MTLDepthStencilState

    private let device: MTLDevice
    private let library: MTLLibrary
    private let commandQueue: MTLCommandQueue

    private let sampleCount: Int
    private let colorPixelFormat: MTLPixelFormat
    private let depthPixelFormat: MTLPixelFormat

    private let sourceScreenColorArgumentBuffer: MTLBuffer
    private let sourceNoScreenColorArgumentBuffer: MTLBuffer
    private let composePipelineState: MTLRenderPipelineState

    // FrameInFlight
    private let frameInFlightManager: PBRFrameInFlightManager

    public init(
        commandQueue: MTLCommandQueue,
        sampleCount: Int = 4,
        colorPixelFormat: MTLPixelFormat = .rgba8Unorm_srgb,
        depthPixelFormat: MTLPixelFormat = .depth32Float,
        maxFramesInFlight: Int = 2
    ) throws {
        self.device = commandQueue.device
        self.commandQueue = commandQueue
        self.library = try device.makePackageLibrary()

        self.sampleCount = sampleCount
        self.colorPixelFormat = colorPixelFormat
        self.depthPixelFormat = depthPixelFormat
        self.shaderConnection = try ShaderConnection(commandQueue: commandQueue)
        self.prefilterSceneGenerator = try PrefilterSceneGenerator(device: device)

        self.pbrPipelineConnector = try PBRPipelineConnector(device: device)
        self.envMapLoader = try EnvironmentMapLoader(commandQueue: commandQueue)
        self.offscreenTextureManager = PBROffscreenTextureManager(
            device: device,
            sampleCount: sampleCount,
            maxFramesInFlight: maxFramesInFlight
        )

        self.writeDSO = try makeLessEqualDepthStencilState(device: device)
        self.noWriteDSO = try makeLessEqualNoWriteDepthStencilState(device: device)

        // setup default env map
        self.defaultEnvMapBundle = try envMapLoader.makeEnvMapBundle(from: CGColor(gray: 0.0, alpha: 1.0))

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

        // screen color arg buffer
        sourceScreenColorArgumentBuffer = device.makeBuffer(
            length: MemoryLayout<PBRScreenColorArguments>.size,
            options: [.storageModeShared]
        )!
        sourceNoScreenColorArgumentBuffer = device.makeBuffer(
            length: MemoryLayout<PBRScreenColorArguments>.size,
            options: [.storageModeShared]
        )!

        // FrameInFlight
        frameInFlightManager = PBRFrameInFlightManager(device: device, maxFramesInFlight: maxFramesInFlight)
    }

    // MARK: - Rendering

    public func render(
        commandBuffer: MTLCommandBuffer,
        context: FinalizedRenderingContext
    ) {
        switch context {
        case let .icb(
            indirectRenderState,
            envMapBundle,
            modelMatrix,
            sceneUniforms,
            cameraIndex,
            freeCameraUniforms,
            animationState,
            renderingState,
            showsSkybox
        ):
            let frameInFlightResources = frameInFlightManager.currentResourcesWith(
                modelMatrix: modelMatrix,
                sceneUniforms: sceneUniforms,
                cameraIndex: cameraIndex,
                freeCameraUniforms: freeCameraUniforms
            )

            var animationFence: MTLFence?
            if let animationState = animationState {
                animationFence = encodeAnimation(
                    meshBundle: indirectRenderState.meshBundle,
                    commandBuffer: commandBuffer,
                    animationState: animationState
                )
            }

            encodeRenderingMesh(
                indirectRenderState: indirectRenderState,
                envMapBundle: envMapBundle,
                commandBuffer: commandBuffer,
                renderPassDescriptor: renderingState.renderPassDescriptor,
                drawableSize: renderingState.drawableSize,
                viewport: renderingState.viewport,
                fragmentParams: frameInFlightResources.sceneUniformsBuffer,
                cameraIndexBuffer: frameInFlightResources.cameraIndexBuffer,
                freeCameraUniformsBuffer: frameInFlightResources.freeCameraUniformsBuffer,
                modelMatrixBuffer: frameInFlightResources.modelMatrixBuffer,
                showsSkybox: showsSkybox,
                waitFence: animationFence
            )
        }
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
            logger.error("Failed to create compute command encoder")
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
            logger.error("Failed to compute world matrices: \(String(describing: error), privacy: .public)")
            return nil
        }

        guard let fence = device.makeFence() else {
            logger.error("Failed to create fence")
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

    private func encodeRenderingMesh(
        indirectRenderState: PBRIndirectRenderState,
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
            logger.error("Failed to create blit command encoder")
            return
        }
        blitEncoder.label = "[SwiftGLTF] Ensure Indirect Buffers Blit Encoder"

        // Ensure buffers for indirect rendering
        let meshBundle = indirectRenderState.meshBundle
        let envMapBundle = envMapBundle ?? defaultEnvMapBundle
        ensureIndirectBuffer(
            blitEncoder: blitEncoder,
            to: indirectRenderState,
            fromSceneUniformsBuffer: fragmentParams,
            fromModelMatrixBuffer: modelMatrixBuffer,
            fromCameraIndexBuffer: cameraIndexBuffer,
            fromFreeCameraUniformsBuffer: freeCameraUniformsBuffer,
            fromEnvMapBuffer: envMapBundle.argBuffer
        )

        // Ensure offscreen textures
        let offscreenResources: PBROffscreenTextureResources
        do {
            offscreenResources = try offscreenTextureManager.resolve(for: drawableSize)
            try ensureOffscreenResources(blitEncoder, from: offscreenResources, to: indirectRenderState)
        } catch {
            logger.error("Failed to resolve offscreen textures")
            return
        }

        blitEncoder.updateFence(blitFence)
        blitEncoder.endEncoding()

        // Pass 1: draw opaque + masked + blended to offscreen
        guard let screenColorRE = commandBuffer.makeRenderCommandEncoder(descriptor: offscreenResources.screenColorRPD) else { return }
        screenColorRE.label = "[SwiftGLTF] PBR Screen Color Render Encoder"
        screenColorRE.setViewport(viewport)
        encodeScreenPass(
            renderEncoder: screenColorRE,
            indirectRenderState: indirectRenderState,
            bundle: meshBundle,
            envMapBundle: envMapBundle,
            showsSkybox: showsSkybox,
            fences: [waitFence, blitFence].compactMap({$0})
        )

        if meshBundle.needsTransmissionPass {
            // Pass 2: Generate prefiltered scene texture
            prefilterSceneGenerator.generate(
                from: offscreenResources.screenColorTexture,
                to: offscreenResources.screenPrefilterTexture,
                commandBuffer: commandBuffer
            )

            // Pass 3: draw transmission to offscreen
            guard let transmissionRE = commandBuffer.makeRenderCommandEncoder(descriptor: offscreenResources.transmissionRPD) else { return }
            transmissionRE.label = "[SwiftGLTF] PBR Transmission Render Encoder"
            transmissionRE.setViewport(viewport)
            encodeTransmissionPass(
                renderEncoder: transmissionRE,
                indirectRenderState: indirectRenderState,
                bundle: meshBundle,
                envMapBundle: envMapBundle,
                screenPrefilterTexture: offscreenResources.screenPrefilterTexture
            )
        }

        // Pass 4: full-screen compose to screen
        guard let composeRE = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }
        composeRE.label = "[SwiftGLTF] PBR Compose Render Encoder"
        encodeComposePass(
            renderEncoder: composeRE,
            screenColorTexture: offscreenResources.screenColorTexture,
            sceneTransmissionTexture: offscreenResources.sceneTransmissionTexture,
            useTransmissionTexture: meshBundle.needsTransmissionPass ? 1 : 0
        )
    }

    // MARK: - Encoding passes

    private func encodeScreenPass(
        renderEncoder: MTLRenderCommandEncoder,
        indirectRenderState: PBRIndirectRenderState,
        bundle: PBRMeshBundle,
        envMapBundle: EnvMapBundle,
        showsSkybox: Bool,
        fences: [MTLFence]
    ) {
        for fence in fences {
            renderEncoder.waitForFence(fence, before: .vertex)
        }

        renderEncoder.useResources(
            bundle.relationTableResources +
            [
                indirectRenderState.skyboxMesh.vertexBuffer,
                indirectRenderState.skyboxMesh.indexBuffer
            ],
            usage: .read,
            stages: [.vertex, .fragment]
        )
        renderEncoder.useHeaps(
            [indirectRenderState.indirectHeap, envMapBundle.heap] + bundle.heaps,
            stages: [.vertex, .fragment]
        )

        if showsSkybox {
            drawWithContext(
                renderEncoder: renderEncoder,
                icb: indirectRenderState.skyboxICBState.icb,
                context: indirectRenderState.skyboxICBState.renderPassContext
            )
        }

        drawWithContext(
            renderEncoder: renderEncoder,
            icb: indirectRenderState.screenColorICBState.icb,
            context: indirectRenderState.screenColorICBState.renderPassContext
        )
        renderEncoder.endEncoding()
    }

    private func encodeTransmissionPass(
        renderEncoder: MTLRenderCommandEncoder,
        indirectRenderState: PBRIndirectRenderState,
        bundle: PBRMeshBundle,
        envMapBundle: EnvMapBundle,
        screenPrefilterTexture: MTLTexture
    ) {
        renderEncoder.useResources(
            bundle.relationTableResources + [screenPrefilterTexture],
            usage: .read,
            stages: [.vertex, .fragment]
        )
        renderEncoder.useHeaps(
            [indirectRenderState.indirectHeap, envMapBundle.heap] + bundle.heaps,
            stages: [.vertex, .fragment]
        )

        drawWithContext(
            renderEncoder: renderEncoder,
            icb: indirectRenderState.transmissionICBState.icb,
            context: indirectRenderState.transmissionICBState.renderPassContext
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

    private func ensureIndirectBuffer(
        blitEncoder: MTLBlitCommandEncoder,
        to state: PBRIndirectRenderState,
        fromSceneUniformsBuffer: MTLBuffer,
        fromModelMatrixBuffer: MTLBuffer,
        fromCameraIndexBuffer: MTLBuffer,
        fromFreeCameraUniformsBuffer: MTLBuffer,
        fromEnvMapBuffer: MTLBuffer
    ) {
        blitEncoder.copy(
            from: fromSceneUniformsBuffer,
            sourceOffset: 0,
            to: state.indirectSceneUniformsBuffer,
            destinationOffset: 0,
            size: MemoryLayout<SceneUniforms>.size
        )
        blitEncoder.copy(
            from: fromModelMatrixBuffer,
            sourceOffset: 0,
            to: state.indirectModelMatrixBuffer,
            destinationOffset: 0,
            size: MemoryLayout<simd_float4x4>.size
        )
        blitEncoder.copy(
            from: fromCameraIndexBuffer,
            sourceOffset: 0,
            to: state.indirectCameraIndexBuffer,
            destinationOffset: 0,
            size: MemoryLayout<Int>.size
        )
        blitEncoder.copy(
            from: fromFreeCameraUniformsBuffer,
            sourceOffset: 0,
            to: state.indirectFreeCameraUniformsBuffer,
            destinationOffset: 0,
            size: MemoryLayout<FreeCameraUniforms>.size
        )
        blitEncoder.copy(
            from: fromEnvMapBuffer,
            sourceOffset: 0,
            to: state.indirectEnvMapArgumentBuffer,
            destinationOffset: 0,
            size: MemoryLayout<PBREnvMapArguments>.size
        )
    }

    private func ensureOffscreenResources(
        _ blitEncoder: MTLBlitCommandEncoder,
        from offscreenResources: PBROffscreenTextureResources,
        to indirectRenderState: PBRIndirectRenderState
    ) throws {
        let sourceScreenColorArgumentBufferPtr = sourceScreenColorArgumentBuffer.contents().bindMemory(to: PBRScreenColorArguments.self, capacity: 1)
        sourceScreenColorArgumentBufferPtr.pointee.sceneColorTexture = offscreenResources.screenColorTexture.gpuResourceID
        sourceScreenColorArgumentBufferPtr.pointee.sceneColorSampler = offscreenResources.sceneColorSampler.gpuResourceID
        sourceScreenColorArgumentBufferPtr.pointee.useSceneColor = true
        blitEncoder.copy(
            from: sourceScreenColorArgumentBuffer,
            sourceOffset: 0,
            to: indirectRenderState.indirectScreenColorArgumentBuffer,
            destinationOffset: 0,
            size: MemoryLayout<PBRScreenColorArguments>.size
        )

        let sourceNoScreenColorArgumentBufferPtr = sourceNoScreenColorArgumentBuffer.contents().bindMemory(to: PBRScreenColorArguments.self, capacity: 1)
        sourceNoScreenColorArgumentBufferPtr.pointee.useSceneColor = false
        blitEncoder.copy(
            from: sourceNoScreenColorArgumentBuffer,
            sourceOffset: 0,
            to: indirectRenderState.indirectNoScreenColorArgumentBuffer,
            destinationOffset: 0,
            size: MemoryLayout<PBRScreenColorArguments>.size
        )
    }
}
