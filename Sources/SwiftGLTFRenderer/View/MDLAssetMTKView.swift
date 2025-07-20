import MetalKit

public class MDLAssetMTKView: MTKView {
    private let commandQueue: MTLCommandQueue
    private var meshes: [MTKMesh]

    private var psoList: [MTLRenderPipelineState]
    private let dso: MTLDepthStencilState

    private var rotationX: Float32 = .pi / 2
    private var rotationY: Float32 = .pi / 2
    private var upSign: Float32 = 1
    private var distance: Float32 = 5

    private var ambient: SIMD3<Float> = SIMD3<Float>(0.1, 0.1, 0.1)

    private let SAMPLING_COUNT = 4

    public init(
        frame: CGRect,
        device: MTLDevice,
        commandQueue: MTLCommandQueue,
        asset: MDLAsset
    ) throws {
        self.commandQueue = commandQueue

        let (_, metalKitMesh) = try MTKMesh.newMeshes(asset: asset, device: device)
        self.meshes = metalKitMesh

        let library = try device.makePackageLibrary()

        // Create a render pipeline descriptor
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = library.makeFunction(name: "blinn_phong_vertex_shader")
        pipelineDescriptor.fragmentFunction = library.makeFunction(name: "blinn_phong_fragment_shader")
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float
        pipelineDescriptor.rasterSampleCount = SAMPLING_COUNT
        var psoList: [MTLRenderPipelineState] = []
        for mesh in meshes {
            pipelineDescriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(mesh.vertexDescriptor)
            let pso = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
            psoList.append(pso)
        }
        self.psoList = psoList

        // Create a depth stencil descriptor
        let depthStencilDescriptor = MTLDepthStencilDescriptor()
        depthStencilDescriptor.depthCompareFunction = .less
        depthStencilDescriptor.isDepthWriteEnabled = true
        guard let depthStencilState = device.makeDepthStencilState(descriptor: depthStencilDescriptor) else {
            throw NSError(domain: "MDLAssetMTKView", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create depth stencil state"])
        }
        self.dso = depthStencilState

        super.init(frame: frame, device: device)

        self.colorPixelFormat = .bgra8Unorm
        self.depthStencilPixelFormat = .depth32Float
        self.clearColor = MTLClearColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
        self.sampleCount = SAMPLING_COUNT

        #if os(iOS)
        setupUIForIOS()
        #elseif os(macOS)
        setupUIForMacOS()
        #endif
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - State Management

    func setAsset(_ asset: MDLAsset) throws {
        let (_, metalKitMesh) = try MTKMesh.newMeshes(asset: asset, device: self.device!)
        self.meshes = metalKitMesh

        var psoList: [MTLRenderPipelineState] = []
        for mesh in meshes {
            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = device!.makeDefaultLibrary()?.makeFunction(name: "mdl_asset_vertex_shader")
            pipelineDescriptor.fragmentFunction = device!.makeDefaultLibrary()?.makeFunction(name: "mdl_asset_fragment_shader")
            pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float
            pipelineDescriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(mesh.vertexDescriptor)
            pipelineDescriptor.rasterSampleCount = SAMPLING_COUNT
            let pso = try device!.makeRenderPipelineState(descriptor: pipelineDescriptor)
            psoList.append(pso)
        }
        self.psoList = psoList
    }

    // MARK: - Rendering

    public override func draw(_ rect: CGRect) {
        guard let drawable = currentDrawable,
              let descriptor = currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }

        // Make buffer

        let model = simd_float4x4(1)
        let eye = SIMD3<Float>(
            distance * cos(rotationX) * sin(rotationY),
            distance * cos(rotationY),
            distance * sin(rotationX) * sin(rotationY)
        )
        let view = lookAt(
            eye: eye,
            target: simd_float3(0, 0, 0),
            up: simd_float3(0, 1, 0)
        )
        let projection = perspectiveMatrix(
            fov: .pi / 3,
            aspect: Float(drawableSize.width / drawableSize.height),
            near: 0.1,
            far: 100.0
        )
        var mvp = projection * view * model
        let mvpBuffer = device!.makeBuffer(
            bytes: &mvp,
            length: MemoryLayout<simd_float4x4>.size,
            options: []
        )!

        var normalMatrix = float3x3(model).transpose.inverse
        let normalBuffer = device!.makeBuffer(
            bytes: &normalMatrix,
            length: MemoryLayout<float3x3>.size,
            options: []
        )!

        var blingPhongUniforms = BlinnPhongSceneUniforms(
            lightPosition: normalize(SIMD3<Float>(0, 1, 1)),
            viewPosition: normalize(eye),
            ambientLight: ambient
        )
        let blingPhongUniformsBuffer = device!.makeBuffer(
            bytes: &blingPhongUniforms,
            length: MemoryLayout<BlinnPhongSceneUniforms>.size,
            options: []
        )!

        // Set up render encoder

        for (mesh, pso) in zip(meshes, psoList) {
            renderEncoder.setRenderPipelineState(pso)
            renderEncoder.setDepthStencilState(dso)

            renderEncoder.setVertexBuffer(mesh.vertexBuffers[0].buffer, offset: 0, index: 0)
            renderEncoder.setVertexBuffer(mvpBuffer, offset: 0, index: 1)
            renderEncoder.setVertexBuffer(normalBuffer, offset: 0, index: 2)
            renderEncoder.setFragmentBuffer(blingPhongUniformsBuffer, offset: 0, index: 0)

            // Draw the mesh

            for submesh in mesh.submeshes {
                renderEncoder.drawIndexedPrimitives(
                    type: submesh.primitiveType,
                    indexCount: submesh.indexCount,
                    indexType: submesh.indexType,
                    indexBuffer: submesh.indexBuffer.buffer,
                    indexBufferOffset: submesh.indexBuffer.offset
                )
            }
        }

        renderEncoder.endEncoding()
        commandBuffer.present(drawable)
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

    func setupUIForMacOS() {
        // No additional setup needed for macOS
    }

    public override func scrollWheel(with event: NSEvent) {
        let multiplier: Float32 = 1
        rotationY = rotationY - multiplier * 2.0 * .pi * Float32(event.scrollingDeltaY) / Float32(self.frame.height)
        upSign = sin(rotationY) >= 0 ? 1 : -1
        rotationX = rotationX - upSign * multiplier * 2.0 * .pi * Float32(event.scrollingDeltaX) / Float32(self.frame.width)
    }

    public override func magnify(with event: NSEvent) {
        let threshold: Float32 = 2
        distance = distance - Float32(event.magnification) * 10.0
        if distance < threshold {
            distance = threshold
        }
    }

    #endif
}
