import SwiftGLTF
import MetalKit
import Img2Cubemap

public enum DisplayType {
    case pbr
    case wireframe
}

public class MDLAssetPBRMTKView: MTKView {
    private let renderer: GLTFRenderer

    private let pbrSceneUniformsBuffer: FrameInFlightBuffer
    private let viewBuffer: FrameInFlightBuffer
    private let projectionBuffer: FrameInFlightBuffer
    private let skyboxVPMatrixBuffer: FrameInFlightBuffer

    private var displayType: DisplayType = .pbr

    private var rotationX: Float32 = -.pi / 2
    private var rotationY: Float32 = .pi / 2
    private var upSign: Float32 = 1
    private var distance: Float32 = 5
    private var targetOffset: SIMD3<Float> = .zero

    private var ambientLightColor: SIMD3<Float> = SIMD3<Float>(1, 1, 1) * 5
    private var lightPosition: SIMD3<Float> = SIMD3<Float>(0, 5, -5)

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

    public init(frame: CGRect, renderer: GLTFRenderer) {
        self.renderer = renderer
        self.frameSemaphores = DispatchSemaphore(value: maxFramesInFlight)

        let device = renderer.device

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
        self.skyboxVPMatrixBuffer = FrameInFlightBuffer(maxFramesInFlight: maxFramesInFlight) {
            device.makeBuffer(
                length: MemoryLayout<simd_float4x4>.size,
                options: .storageModeShared
            )!
        }

        super.init(frame: frame, device: device)

        self.colorPixelFormat = renderer.colorPixelFormat
        self.depthStencilPixelFormat = renderer.depthPixelFormat
        self.sampleCount = renderer.sampleCount
        self.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1.0)

        #if os(iOS)
        setupUIForIOS()
        #elseif os(macOS)
        #endif
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - State Management

    func resetCamera() {
        rotationX = -.pi / 2
        rotationY = .pi / 2
        upSign = 1
        distance = 5
        targetOffset = .zero
    }

    func setDisplayType(_ type: DisplayType) {
        displayType = type
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

    // MARK: - Rendering

    public override func draw(_ rect: CGRect) {
        guard let drawable = currentDrawable,
              let descriptor = currentRenderPassDescriptor,
              let commandBuffer = renderer.commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }

        // Update frame buffer index
        frameSemaphores.wait()
        currentBuffer = (currentBuffer + 1) % maxFramesInFlight

        // Update buffers
        updateSkyboxBuffer(
            toVPMatrixBuffer: skyboxVPMatrixBuffer.buffer(currentBuffer),
            rotationX: rotationX,
            rotationY: rotationY,
            upSign: upSign,
            drawableSize: drawableSize
        )
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

        // Rendering
        renderer.render(
            using: renderEncoder,
            type: displayType,
            view: viewBuffer.buffer(currentBuffer),
            projection: projectionBuffer.buffer(currentBuffer),
            pbrScene: pbrSceneUniformsBuffer.buffer(currentBuffer),
            skyboxVP: skyboxVPMatrixBuffer.buffer(currentBuffer),
            offset: targetOffset
        )

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
