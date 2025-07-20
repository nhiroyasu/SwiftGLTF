import SwiftGLTF
import MetalKit
import Img2Cubemap

public class MDLAssetPBRMTKView: MTKView {
    private var meshes: [PBRMesh]

    private let commandQueue: MTLCommandQueue
    private let dso: MTLDepthStencilState
    private let pbrSceneUniformsBuffer: FrameInFlightBuffer
    private let viewBuffer: FrameInFlightBuffer
    private let projectionBuffer: FrameInFlightBuffer

    private let specularCubeMapTexture: MTLTexture
    private let irradianceCubeMapTexture: MTLTexture
    private let brdfLUT: MTLTexture

    let skyboxCubeVertexBuffer: MTLBuffer
    let skyboxCubeIndexBuffer: MTLBuffer
    let skyboxVPMatrixBuffer: FrameInFlightBuffer
    let skyboxPSO: MTLRenderPipelineState
    let skyboxDSO: MTLDepthStencilState

    private var rotationX: Float32 = -.pi / 2
    private var rotationY: Float32 = .pi / 2
    private var upSign: Float32 = 1
    private var distance: Float32 = 5
    private var targetOffset: SIMD3<Float> = .zero

    private var ambientLightColor: SIMD3<Float> = SIMD3<Float>(1, 1, 1) * 5
    private var lightPosition: SIMD3<Float> = SIMD3<Float>(0, 5, -5)

    private let SAMPLING_COUNT = 4
    private let IRRADIANCE_SIZE = 128

    private let loaderConfig: MDLAssetLoaderPipelineStateConfig
    private let shaderConnection: ShaderConnection

    private let maxFramesInFlight = 2
    private var currentBuffer = 0
    private let frameSemaphores: DispatchSemaphore

    var eye: SIMD3<Float> {
        SIMD3<Float>(
            distance * cos(rotationX) * sin(rotationY),
            distance * cos(rotationY),
            distance * sin(rotationX) * sin(rotationY)
        )
    }

    public init(
        frame: CGRect,
        device: MTLDevice,
        commandQueue: MTLCommandQueue,
        asset: MDLAsset
    ) async throws {
        self.commandQueue = commandQueue

        let library = try device.makeDefaultLibrary(bundle: Bundle.module)

        self.shaderConnection = ShaderConnection(device: device, commandQueue: commandQueue)

        // Load environment textures
        guard let envMapUrl = Bundle.main.url(forResource: "env_map", withExtension: "exr") else {
            throw NSError(domain: "MDLAssetMTKView", code: 0, userInfo: [NSLocalizedDescriptionKey: "Environment map not found"])
        }
        self.specularCubeMapTexture = try await generateCubeTexture(device: device, exr: envMapUrl)
        self.irradianceCubeMapTexture = generateIrradianceTexture(
            commandQueue: commandQueue,
            library: library,
            envMap: specularCubeMapTexture,
            size: IRRADIANCE_SIZE
        )
        self.brdfLUT = generateBRDFLUT(
            commandQueue: commandQueue,
            library: library,
            width: specularCubeMapTexture.width,
            height: specularCubeMapTexture.height
        )

        // Load meshes from the MDLAsset

        loaderConfig = MDLAssetLoaderPipelineStateConfig(
            pntucVertexShader: library.makeFunction(name: "pntuc_vertex_shader")!,
            pntuVertexShader: library.makeFunction(name: "pntu_vertex_shader")!,
            pntcVertexShader: library.makeFunction(name: "pntc_vertex_shader")!,
            pntVertexShader: library.makeFunction(name: "pnt_vertex_shader")!,
            pncVertexShader: library.makeFunction(name: "pnc_vertex_shader")!,
            pnVertexShader: library.makeFunction(name: "pn_vertex_shader")!,
            pbrFragmentShader: library.makeFunction(name: "pbr_shader")!,
            sampleCount: SAMPLING_COUNT
        )

        let loader = PBRMeshLoader(
            asset: asset,
            shaderConnection: shaderConnection,
            pipelineStateConfig: loaderConfig
        )
        self.meshes = try loader.loadMeshes(device: device)

        // Create a depth stencil descriptor
        let depthStencilDescriptor = MTLDepthStencilDescriptor()
        depthStencilDescriptor.depthCompareFunction = .less
        depthStencilDescriptor.isDepthWriteEnabled = true
        guard let depthStencilState = device.makeDepthStencilState(descriptor: depthStencilDescriptor) else {
            throw NSError(domain: "MDLAssetMTKView", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create depth stencil state"])
        }
        self.dso = depthStencilState

        // Create buffers
        self.pbrSceneUniformsBuffer = FrameInFlightBuffer(maxFramesInFlight: maxFramesInFlight) {
            device.makeBuffer(
                length: MemoryLayout<PBRSceneUniforms>.size,
                options: []
            )!
        }
        self.viewBuffer = FrameInFlightBuffer(maxFramesInFlight: maxFramesInFlight) {
            device.makeBuffer(
                length: MemoryLayout<float4x4>.size,
                options: []
            )!
        }
        self.projectionBuffer = FrameInFlightBuffer(maxFramesInFlight: maxFramesInFlight) {
            device.makeBuffer(
                length: MemoryLayout<float4x4>.size,
                options: []
            )!
        }

        // Create skybox buffers and pipeline state
        let skyboxPsoDescriptor = MTLRenderPipelineDescriptor()
        skyboxPsoDescriptor.label = "Skybox Pipeline"
        skyboxPsoDescriptor.vertexFunction = library.makeFunction(name: "skybox_vertex_shader")
        skyboxPsoDescriptor.fragmentFunction = library.makeFunction(name: "skybox_fragment_shader")
        skyboxPsoDescriptor.colorAttachments[0].pixelFormat = .rgba16Float
        skyboxPsoDescriptor.depthAttachmentPixelFormat = .depth32Float
        skyboxPsoDescriptor.rasterSampleCount = SAMPLING_COUNT
        self.skyboxPSO = try await device.makeRenderPipelineState(descriptor: skyboxPsoDescriptor)

        let skyboxDSODescriptor = MTLDepthStencilDescriptor()
        skyboxDSODescriptor.depthCompareFunction = .always
        skyboxDSODescriptor.isDepthWriteEnabled = false
        skyboxDSODescriptor.label = "Skybox depth stencil"
        self.skyboxDSO = device.makeDepthStencilState(descriptor: skyboxDSODescriptor)!

        let skyboxCube = Cube(size: 1)
        self.skyboxCubeVertexBuffer = device.makeBuffer(
            bytes: skyboxCube.vertices,
            length: MemoryLayout<Float>.size * skyboxCube.vertices.count,
            options: .storageModeShared
        )!
        self.skyboxCubeIndexBuffer = device.makeBuffer(
            bytes: skyboxCube.indices,
            length: MemoryLayout<UInt16>.size * skyboxCube.indices.count,
            options: .storageModeShared
        )!
        self.skyboxVPMatrixBuffer = FrameInFlightBuffer(maxFramesInFlight: maxFramesInFlight) {
            device.makeBuffer(
                length: MemoryLayout<simd_float4x4>.size,
                options: .storageModeShared
            )!
        }

        frameSemaphores = DispatchSemaphore(value: maxFramesInFlight)

        super.init(frame: frame, device: device)

        self.colorPixelFormat = .rgba16Float
        self.depthStencilPixelFormat = .depth32Float
        self.clearColor = MTLClearColor(red: srgbToLinear(0.1), green: srgbToLinear(0.1), blue: srgbToLinear(0.1), alpha: 1.0)
        self.sampleCount = SAMPLING_COUNT

        #if os(iOS)
        setupUIForIOS()
        #elseif os(macOS)
        #endif
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - State Management

    public func setAsset(_ asset: MDLAsset) throws {
        guard let device = self.device else {
            throw NSError(domain: "MDLAssetMTKView", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to set asset"])
        }

        let loader = PBRMeshLoader(
            asset: asset,
            shaderConnection: shaderConnection,
            pipelineStateConfig: loaderConfig
        )
        self.meshes = try loader.loadMeshes(device: device)
        resetCamera()
    }

    func resetCamera() {
        rotationX = -.pi / 2
        rotationY = .pi / 2
        upSign = 1
        distance = 5
        targetOffset = .zero
    }

    // MARK: - Buffer Management

    private func updateSkyboxBuffer(
        toVPMatrixBuffer: MTLBuffer,
        rotationX: Float32,
        rotationY: Float32,
        upSign: Float32,
        drawableSize: CGSize
    ) {
        let skyboxTarget = SIMD3<Float>(
            -cos(rotationX) * sin(rotationY),
            -cos(rotationY),
            -sin(rotationX) * sin(rotationY)
        )
        let skyboxViewMatrix = lookAt(
            eye: SIMD3<Float>(0, 0, 0),
            target: skyboxTarget,
            up: SIMD3<Float>(0, upSign, 0)
        )
        let skyboxProjectionMatrix = perspectiveMatrix(
            fov: .pi / 3,
            aspect: Float(drawableSize.width / drawableSize.height),
            near: 0.1,
            far: 100.0
        )
        var skyboxVPMatrix = skyboxProjectionMatrix * skyboxViewMatrix
        toVPMatrixBuffer.contents().copyMemory(
            from: &skyboxVPMatrix,
            byteCount: MemoryLayout<simd_float4x4>.size
        )
    }

    private func updateSceneBuffer(
        toViewBuffer: MTLBuffer,
        toProjectionBuffer: MTLBuffer,
        toPBRSceneUniformsBuffer: MTLBuffer,
        eye: SIMD3<Float>,
        lightPosition: SIMD3<Float>,
        ambientLightColor: SIMD3<Float>,
        upSign: Float32,
        drawableSize: CGSize
    ) {
        var view = lookAt(
            eye: eye,
            target: simd_float3(0, 0, 0),
            up: simd_float3(0, upSign, 0)
        )
        toViewBuffer.contents().copyMemory(
            from: &view,
            byteCount: MemoryLayout<float4x4>.size
        )

        var projection = perspectiveMatrix(
            fov: .pi / 3,
            aspect: Float(drawableSize.width / drawableSize.height),
            near: 0.1,
            far: 1000.0
        )
        toProjectionBuffer.contents().copyMemory(
            from: &projection,
            byteCount: MemoryLayout<float4x4>.size
        )

        var pbrSceneUniforms = PBRSceneUniforms(
            lightPosition: lightPosition,
            viewPosition: eye,
            ambientLightColor: ambientLightColor
        )
        toPBRSceneUniformsBuffer.contents().copyMemory(
            from: &pbrSceneUniforms,
            byteCount: MemoryLayout<PBRSceneUniforms>.size
        )
    }

    private func updateMeshBuffer(
        toMesh mesh: PBRMesh,
        targetOffset: SIMD3<Float>
    ) {
        let modelTransform = mesh.transform
        let offsetTranslation = translationMatrix(targetOffset.x, targetOffset.y, targetOffset.z)
        var model = offsetTranslation * modelTransform
        mesh.modelBuffer.contents().copyMemory(from: &model, byteCount: MemoryLayout<float4x4>.size)

        var normalMatrix = float3x3(model).transpose.inverse
        mesh.normalMatrixBuffer.contents().copyMemory(from: &normalMatrix, byteCount: MemoryLayout<float3x3>.size)
    }

    // MARK: - Rendering

    public override func draw(_ rect: CGRect) {
        guard let drawable = currentDrawable,
              let descriptor = currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }

        // Update frame buffer index
        frameSemaphores.wait()
        currentBuffer = (currentBuffer + 1) % maxFramesInFlight

        // Draw Skybox
        updateSkyboxBuffer(
            toVPMatrixBuffer: skyboxVPMatrixBuffer.buffer(currentBuffer),
            rotationX: rotationX,
            rotationY: rotationY,
            upSign: upSign,
            drawableSize: drawableSize
        )
        drawSkybox(
            renderEncoder: renderEncoder,
            pso: skyboxPSO,
            dso: skyboxDSO,
            vertexBuffer: skyboxCubeVertexBuffer,
            indexBuffer: skyboxCubeIndexBuffer,
            indexCount: skyboxCubeIndexBuffer.length / MemoryLayout<UInt16>.size,
            indexType: .uint16,
            vpMatrixBuffer: skyboxVPMatrixBuffer.buffer(currentBuffer),
            specularCubeMapTexture: specularCubeMapTexture
        )

        // Draw meshes
        updateSceneBuffer(
            toViewBuffer: viewBuffer.buffer(currentBuffer),
            toProjectionBuffer: projectionBuffer.buffer(currentBuffer),
            toPBRSceneUniformsBuffer: pbrSceneUniformsBuffer.buffer(currentBuffer),
            eye: eye,
            lightPosition: lightPosition,
            ambientLightColor: ambientLightColor,
            upSign: upSign,
            drawableSize: drawableSize
        )
        for mesh in meshes {
            updateMeshBuffer(toMesh: mesh, targetOffset: targetOffset)
            drawMesh(
                renderEncoder: renderEncoder,
                mesh: mesh,
                dso: dso,
                viewBuffer: viewBuffer.buffer(currentBuffer),
                projectionBuffer: projectionBuffer.buffer(currentBuffer),
                pbrSceneUniformsBuffer: pbrSceneUniformsBuffer.buffer(currentBuffer),
                specularCubeMapTexture: specularCubeMapTexture,
                irradianceCubeMapTexture: irradianceCubeMapTexture,
                brdfLUT: brdfLUT
            )
        }

        // Finalize rendering

        renderEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.addCompletedHandler { [weak frameSemaphores] _ in
            frameSemaphores?.signal()
        }
        commandBuffer.commit()
    }

    // MARK: - UI Setup

    #if os(iOS)
    func setupUIForIOS() {
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        self.addGestureRecognizer(panGesture)

        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        self.addGestureRecognizer(pinchGesture)

    }

    var prevTranslation: CGPoint = .zero
    @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            prevTranslation = gesture.translation(in: self)
        case .changed:
            let deltaY = gesture.translation(in: self).y - prevTranslation.y
            let deltaX = gesture.translation(in: self).x - prevTranslation.x
            prevTranslation = gesture.translation(in: self)

            let multiplier: Float32 = 1
            rotationY = rotationY - multiplier * 2.0 * .pi * Float32(deltaY) / Float32(self.frame.height)
            upSign = sin(rotationY) >= 0 ? 1 : -1
            rotationX = rotationX - upSign * multiplier * 2.0 * .pi * Float32(deltaX) / Float32(self.frame.width)
        case .ended, .cancelled:
            prevTranslation = .zero
        default:
            break
        }
    }

    @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began, .changed:
            distance /= Float(gesture.scale)
            gesture.scale = 1.0
        default:
            break
        }
    }

    #elseif os(macOS)

    public override func scrollWheel(with event: NSEvent) {
        // Shift + scroll: pan camera (move eye & target in world space), otherwise rotate camera
        if event.modifierFlags.contains(.shift) {
            let panMultiplier: Float32 = 0.01
            let dx = Float32(event.scrollingDeltaX)
            let dy = Float32(event.scrollingDeltaY)

            targetOffset.x += panMultiplier * (dx * cos(rotationX + .pi / 2))
            targetOffset.y -= panMultiplier * dy
            targetOffset.z += panMultiplier * (dx * sin(rotationX + .pi / 2))
        } else {
            let multiplier: Float32 = 1
            rotationY -= multiplier * 2.0 * .pi * Float32(event.scrollingDeltaY) / Float32(self.frame.height)
            upSign = sin(rotationY) >= 0 ? 1 : -1
            rotationX -= upSign * multiplier * 2.0 * .pi * Float32(event.scrollingDeltaX) / Float32(self.frame.width)
        }
    }

    public override func magnify(with event: NSEvent) {
        let threshold: Float32 = 0.1
        distance = distance - Float32(event.magnification) * 10.0
        if distance < threshold {
            distance = threshold
        }
    }

    #endif
}
