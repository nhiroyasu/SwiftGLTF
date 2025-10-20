import SwiftGLTFParser
import SwiftGLTFShaderTypes
import SwiftGLTFRenderer
import SwiftGLTFCore
import MetalKit
import os.log
import QuartzCore

@MainActor
public class GLTFView: MTKView {
    private let commandQueue: MTLCommandQueue
    private let renderer: PBRRenderer
    private let sceneUniformsBuffer: FrameInFlightBuffer
    private let mvpUniformBuffer: FrameInFlightBuffer

    // MARK: - Display State
    private var displayType: DisplayType = .loading {
        didSet { onChange(displayType) }
    }
    private var freeCameraRX: Float32 = -.pi / 2
    private var freeCameraRY: Float32 = .pi / 2
    private var freeCameraUpSign: Float32 = 1
    private var freeCameraDistance: Float32 = 5
    private var freeCameraTarget: SIMD3<Float> = .zero
    private var freeCameraPos: SIMD3<Float> {
        SIMD3<Float>(
            freeCameraDistance * cos(freeCameraRX) * sin(freeCameraRY),
            freeCameraDistance * cos(freeCameraRY),
            freeCameraDistance * sin(freeCameraRX) * sin(freeCameraRY)
        )
    }
    private var eye: SIMD3<Float> { freeCameraTarget + freeCameraPos }
    private var showDebugHUD: Bool

    // MARK: - Lighting
    private let defaultAmbientLightColor: SIMD3<Float> = SIMD3<Float>(1, 1, 1) * 5
    private let defaultLightPosition: SIMD3<Float> = SIMD3<Float>(0, 5, -5)

    private var ambientLightColor: SIMD3<Float>
    private var lightPosition: SIMD3<Float>

    // MARK: - Frame Management
    private let maxFramesInFlight = 2
    private var currentBuffer = 0
    private let frameSemaphores: DispatchSemaphore

    // MARK: - Animation state
    private var enabledAnimation: Bool = true
    private var animationState = RendererAnimationState(time: 0, speed: 1, isLooping: true)
    private var lastFrameTime: CFTimeInterval?

    public init(
        frame: CGRect,
        device: MTLDevice = MTLCreateSystemDefaultDevice()!,
        showDebugHUD: Bool = false
    ) throws {
        let device = device
        if let commandQueue = device.makeCommandQueue() {
            self.commandQueue = commandQueue
        } else {
            throw SwiftGLTFError.makeRender(.commandQueueCreateFailed, context: .capture(stage: .render))
        }

        let sampleCount = 4
        let colorPixelFormat: MTLPixelFormat = .rgba8Unorm_srgb
        let depthPixelFormat: MTLPixelFormat = .depth32Float

        self.showDebugHUD = showDebugHUD
        self.ambientLightColor = defaultAmbientLightColor
        self.lightPosition = defaultLightPosition

        self.renderer = try PBRRenderer(
            commandQueue: commandQueue,
            sampleCount: sampleCount,
            colorPixelFormat: colorPixelFormat,
            depthPixelFormat: depthPixelFormat
        )

        self.frameSemaphores = DispatchSemaphore(value: maxFramesInFlight)

        self.sceneUniformsBuffer = FrameInFlightBuffer(maxFramesInFlight: maxFramesInFlight) {
            device.makeBuffer(
                length: MemoryLayout<SceneUniforms>.size,
                options: []
            )!
        }
        self.mvpUniformBuffer = FrameInFlightBuffer(maxFramesInFlight: maxFramesInFlight) {
            device.makeBuffer(
                length: MemoryLayout<MVPUniform>.size,
                options: .storageModeShared
            )!
        }

        super.init(frame: frame, device: device)

        self.colorPixelFormat = colorPixelFormat
        self.depthStencilPixelFormat = depthPixelFormat
        self.sampleCount = sampleCount
        self.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1.0)
        self.isPaused = true
        #if os(macOS)
        self.colorspace = CGColorSpaceCreateDeviceRGB()
        #endif

        setupUI()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - State Management

    public func load(gltf url: URL, sceneIndex: Int?) async {
        do {
            displayType = .loading
            defer { displayType = .drawable }
            let asset = try await makeMDLAsset(from: url)
            try await renderer.load(from: asset, sceneIndex: sceneIndex)
        } catch {
            os_log("Failed to load asset from URL: %@", type: .error, error.localizedDescription)
            displayType = .error("Failed to load asset from URL: \(error.localizedDescription)")
        }
    }

    public func load(environment url: URL) async {
        do {
            displayType = .loading
            defer { displayType = .drawable }
            try await renderer.setEnvironment(url: url)
        } catch {
            os_log("Failed to load environment map from URL: %@", type: .error, error.localizedDescription)
        }
    }

    public func resetCamera() {
        freeCameraRX = -.pi / 2
        freeCameraRY = .pi / 2
        freeCameraUpSign = 1
        freeCameraDistance = 5
        freeCameraTarget = .zero
        updateCameraHUD()
    }

    private func resetLight() {
        lightPosition = defaultLightPosition
        ambientLightColor = defaultAmbientLightColor
        updateCameraHUD()
    }

    // MARK: - Buffer Management

    private func updateSceneBuffer(
        toVertexParams: MTLBuffer,
        toFragmentParams: MTLBuffer,
        eye: SIMD3<Float>,
        target: SIMD3<Float>,
        lightPosition: SIMD3<Float>,
        ambientLightColor: SIMD3<Float>,
        upSign: Float32,
        drawableSize: CGSize
    ) {
        let view = lookAt(
            eye: eye,
            target: target,
            up: simd_float3(0, upSign, 0)
        )

        let aspect = Float(drawableSize.width / drawableSize.height)
        let fovY = Float.pi / 3.0
        let fovX = 2 * atan(tan(fovY / 2) * aspect)
        let projection = perspectiveMatrix(
            fov: fovY,
            aspect: aspect,
            near: 0.1,
            far: 1000.0
        )
        var vpUniforms = MVPUniform(
            view: view,
            projection: projection,
            externalTransform: matrix_identity_float4x4
        )
        toVertexParams.contents().copyMemory(
            from: &vpUniforms,
            byteCount: MemoryLayout<MVPUniform>.size
        )

        var pbrSceneUniforms = SceneUniforms(
            lightPosition: lightPosition,
            viewPosition: eye,
            ambientLightColor: ambientLightColor,
            viewportSize: SIMD2<Float>(Float(drawableSize.width), Float(drawableSize.height)),
            fov: SIMD2<Float>(fovX, fovY),
            camRight: SIMD3<Float>(1, 0, 0),
            camUp: SIMD3<Float>(0, 1, 0)
        )
        toFragmentParams.contents().copyMemory(
            from: &pbrSceneUniforms,
            byteCount: MemoryLayout<SceneUniforms>.size
        )
    }

    // MARK: - Rendering

    public override func draw(_ rect: CGRect) {
        guard let drawable = currentDrawable,
              let descriptor = currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }

        // Update frame buffer index
        frameSemaphores.wait()
        currentBuffer = (currentBuffer + 1) % maxFramesInFlight

        // Update buffers
        updateSceneBuffer(
            toVertexParams: mvpUniformBuffer.buffer(currentBuffer),
            toFragmentParams: sceneUniformsBuffer.buffer(currentBuffer),
            eye: eye,
            target: freeCameraTarget,
            lightPosition: lightPosition,
            ambientLightColor: ambientLightColor,
            upSign: freeCameraUpSign,
            drawableSize: drawableSize
        )

        // Advance animation and apply to the asset if available
        var animationFence: MTLFence?
        if let lastTime = lastFrameTime, enabledAnimation {
            let now = CACurrentMediaTime()
            let dt = now - lastTime
            lastFrameTime = now
            animationState.time += Float(dt) * animationState.speed

            animationFence = renderer.animation(
                commandBuffer: commandBuffer,
                animationState: animationState
            )
        } else {
            lastFrameTime = CACurrentMediaTime()
        }

        // Rendering
        renderer.render(
            commandBuffer: commandBuffer,
            renderPassDescriptor: descriptor,
            drawableSize: drawableSize,
            mvpUniformBuffer: mvpUniformBuffer.buffer(currentBuffer),
            fragmentParams: sceneUniformsBuffer.buffer(currentBuffer),
            viewPos: eye,
            waitFence: animationFence
        )
        commandBuffer.present(drawable)
        commandBuffer.addCompletedHandler { [weak frameSemaphores] _ in
            frameSemaphores?.signal()
        }
        commandBuffer.commit()
    }

    // MARK: - UI

    #if os(iOS)
    private let messageLabel = UILabel()
    private var debugHUDView: CameraDebugHUDView?

    func setupUI() {
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        self.addGestureRecognizer(panGesture)

        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        self.addGestureRecognizer(pinchGesture)

        messageLabel.isHidden = true
        addSubview(messageLabel)

        if showDebugHUD {
            let hud = CameraDebugHUDView()
            hud.translatesAutoresizingMaskIntoConstraints = false
            hud.onReset = { [weak self] in self?.resetCamera() }
            hud.onLightPositionChange = { [weak self] value in
                self?.lightPosition = value
                self?.updateCameraHUD()
            }
            hud.onAmbientLightColorChange = { [weak self] value in
                self?.ambientLightColor = value
                self?.updateCameraHUD()
            }
            hud.onLightReset = { [weak self] in
                guard let self else { return }
                self.resetLight()
            }
            addSubview(hud)
            debugHUDView = hud

            let guide = safeAreaLayoutGuide
            NSLayoutConstraint.activate([
                hud.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 12),
                hud.topAnchor.constraint(equalTo: guide.topAnchor, constant: 12)
            ])

            hud.update(
                position: eye,
                lightPosition: lightPosition,
                ambientLightColor: ambientLightColor
            )
        }
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
            freeCameraRY = freeCameraRY - multiplier * 2.0 * .pi * Float32(deltaY) / Float32(self.frame.height)
            freeCameraUpSign = sin(freeCameraRY) >= 0 ? 1 : -1
            freeCameraRX = freeCameraRX - freeCameraUpSign * multiplier * 2.0 * .pi * Float32(deltaX) / Float32(self.frame.width)
            updateCameraHUD()
        case .ended, .cancelled:
            prevTranslation = .zero
        default:
            break
        }
    }

    @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began, .changed:
            freeCameraDistance /= Float(gesture.scale)
            gesture.scale = 1.0
            updateCameraHUD()
        default:
            break
        }
    }

    func showError(_ message: String) {
        messageLabel.text = message
        messageLabel.textColor = .systemRed
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }

    #elseif os(macOS)

    private let messageLabel = NSTextField()
    private var debugHUDView: CameraDebugHUDView?

    private func setupUI() {
        messageLabel.isEditable = false
        messageLabel.isBezeled = false
        messageLabel.drawsBackground = false
        messageLabel.autoresizingMask = [.width, .height]
        messageLabel.isHidden = true
        addSubview(messageLabel)

        if showDebugHUD {
            let hud = CameraDebugHUDView()
            hud.translatesAutoresizingMaskIntoConstraints = false
            hud.onReset = { [weak self] in self?.resetCamera() }
            hud.onLightPositionChange = { [weak self] value in
                self?.lightPosition = value
                self?.updateCameraHUD()
            }
            hud.onAmbientLightColorChange = { [weak self] value in
                self?.ambientLightColor = value
                self?.updateCameraHUD()
            }
            hud.onLightReset = { [weak self] in
                guard let self else { return }
                self.resetLight()
            }
            addSubview(hud)
            debugHUDView = hud

            NSLayoutConstraint.activate([
                hud.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 12),
                hud.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 12)
            ])

            hud.update(
                position: eye,
                lightPosition: lightPosition,
                ambientLightColor: ambientLightColor
            )
        }
    }

    public override func scrollWheel(with event: NSEvent) {
        // Shift + scroll: pan camera (move eye & target in world space), otherwise rotate camera
        if event.modifierFlags.contains(.shift) {
            let panMultiplier: Float32 = 0.01
            let dx = Float32(event.scrollingDeltaX)
            let dy = Float32(event.scrollingDeltaY)

            freeCameraTarget.x -= panMultiplier * (dx * cos(freeCameraRX + .pi / 2))
            freeCameraTarget.y += panMultiplier * dy
            freeCameraTarget.z -= panMultiplier * (dx * sin(freeCameraRX + .pi / 2))
        } else {
            let multiplier: Float32 = 1
            freeCameraRY -= multiplier * 2.0 * .pi * Float32(event.scrollingDeltaY) / Float32(self.frame.height)
            freeCameraUpSign = sin(freeCameraRY) >= 0 ? 1 : -1
            freeCameraRX -= freeCameraUpSign * multiplier * 2.0 * .pi * Float32(event.scrollingDeltaX) / Float32(self.frame.width)
        }
        updateCameraHUD()
    }

    public override func magnify(with event: NSEvent) {
        let threshold: Float32 = 0.1
        freeCameraDistance = freeCameraDistance - Float32(event.magnification) * 10.0
        if freeCameraDistance < threshold {
            freeCameraDistance = threshold
        }
        updateCameraHUD()
    }

    func showError(_ message: String) {
        messageLabel.stringValue = message
        messageLabel.textColor = .systemRed
        messageLabel.alignment = .center
    }

    #endif

    private func updateCameraHUD() {
        guard showDebugHUD else { return }
        debugHUDView?.update(
            position: eye,
            lightPosition: lightPosition,
            ambientLightColor: ambientLightColor
        )
    }

    func onChange(_ displayType: DisplayType) {
        switch displayType {
        case .loading:
            isPaused = true
            messageLabel.isHidden = true
        case .drawable:
            isPaused = false
            messageLabel.isHidden = true
        case .error(let message):
            isPaused = true
            messageLabel.isHidden = false
            showError(message)
        }
    }

    // MARK: - Internal Types

    enum DisplayType {
        case loading
        case drawable
        case error(String)
    }
}
