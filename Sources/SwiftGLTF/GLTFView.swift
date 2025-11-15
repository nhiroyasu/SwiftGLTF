import SwiftGLTFParser
import SwiftGLTFShaderTypes
import SwiftGLTFRenderer
import SwiftGLTFCore
import MetalKit
import os.log
import QuartzCore

public protocol GLTFViewDelegate: AnyObject {
    func loaded(gltf: GLTF?, error: Error?)
}

/// A Metal-backed view for loading and rendering glTF assets with a PBR renderer.
///
/// This view manages GPU resources, simple free-camera controls, frame-in-flight buffers,
/// and optional debug HUD. It exposes convenience APIs to load a glTF asset and an
/// environment map, and renders using `PBRRenderer`.
@MainActor
public class GLTFView: MTKView {
    private let commandQueue: MTLCommandQueue
    private let renderer: PBRRenderer
    private let sceneUniformsBuffer: FrameInFlightBuffer
    private let modelMatrixBuffer: FrameInFlightBuffer
    private let cameraIndexBuffer: FrameInFlightBuffer
    private let freeCameraUniformsBuffer: FrameInFlightBuffer
    private var loadedGLTF: GLTF?

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

    // MARK: - Load Handlers
    public var gltfLoadHandler: ((Result<GLTF, Error>) -> Void)?

    // MARK: - Lighting
    private let defaultAmbientLightColor: SIMD3<Float> = SIMD3<Float>(1, 1, 1) * 5
    private let defaultLightPosition: SIMD3<Float> = SIMD3<Float>(0, 5, -5)

    private var ambientLightColor: SIMD3<Float>
    private var lightPosition: SIMD3<Float>

    // MARK: - Camera
    public var cameraIndex: Int? = nil

    // MARK: - Frame Management
    private let maxFramesInFlight = 2
    private var currentBuffer = 0
    private let frameSemaphores: DispatchSemaphore

    // MARK: - Animation state
    private var enabledAnimation: Bool = true
    private var animationState = RendererAnimationState(time: 0, speed: 1, isLooping: true)
    private var lastFrameTime: CFTimeInterval?

    /// Creates a GLTFView configured for PBR rendering.
    ///
    /// - Parameters:
    ///   - frame: The initial frame rectangle of the view.
    ///   - device: The Metal device to use. Defaults to the system default device.
    ///   - showDebugHUD: Whether to display a simple on-screen camera/light HUD.
    /// - Throws: An error if the Metal command queue or renderer cannot be created.
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
        self.modelMatrixBuffer = FrameInFlightBuffer(maxFramesInFlight: maxFramesInFlight) {
            device.makeBuffer(
                length: MemoryLayout<float4x4>.size,
                options: .storageModeShared
            )!
        }
        self.cameraIndexBuffer = FrameInFlightBuffer(maxFramesInFlight: maxFramesInFlight) {
            device.makeBuffer(
                length: MemoryLayout<Int>.size,
                options: .storageModeShared
            )!
        }
        self.freeCameraUniformsBuffer = FrameInFlightBuffer(maxFramesInFlight: maxFramesInFlight) {
            device.makeBuffer(
                length: MemoryLayout<FreeCameraUniforms>.size,
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

    // MARK: - Public Interface

    /// Loads and displays a glTF asset from the specified URL.
    ///
    /// This method parses the glTF file, creates an `MDLAsset`, uploads
    /// the necessary GPU resources, and switches the view into drawable state on success.
    ///
    /// - Parameters:
    ///   - url: The file URL of the glTF (either .gltf or .glb via Data contents).
    ///   - sceneIndex: The index of the scene to display. Pass `nil` to use the default scene.
    /// - Note: The delegate `gltfDelegate` will be notified on completion with either the parsed `GLTF` or an error.
    public func load(gltf url: URL, sceneIndex: Int? = nil, animationIndex: Int? = nil) {
        do {
            displayType = .loading
            defer { displayType = .drawable }
            let data = try Data(contentsOf: url)
            let gltfBundle = try loadGLTF(from: data, baseURL: url.deletingLastPathComponent())
            let asset = try makeMDLAsset(from: gltfBundle)
            try renderer.load(from: asset, sceneIndex: sceneIndex, animationIndex: animationIndex)
            loadedGLTF = gltfBundle.gltf
            gltfLoadHandler?(.success(gltfBundle.gltf))
        } catch {
            os_log("Failed to load asset from URL: %@", type: .error, error.localizedDescription)
            displayType = .error("Failed to load asset from URL: \(error.localizedDescription)")
            loadedGLTF = nil
            gltfLoadHandler?(.failure(error) )
        }
    }

    /// Loads an image-based lighting (IBL) environment map.
    ///
    /// Sets the renderer's environment from a file URL (e.g., HDR/EXR), then
    /// returns the view to drawable state.
    ///
    /// - Parameter url: The file URL of the environment map to use for lighting/reflections.
    /// - Important: Large HDR/EXR files may take time to process depending on device capabilities.
    public func load(environment url: URL) {
        do {
            displayType = .loading
            defer { displayType = .drawable }
            try renderer.setEnvironment(url: url)
        } catch {
            os_log("Failed to load environment map from URL: %@", type: .error, error.localizedDescription)
        }
    }

    /// Resets the free camera to its default position and orientation.
    ///
    /// Restores yaw/pitch, distance, up direction, and target to defaults and
    /// updates the debug HUD if enabled.
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
        toModelMatrix: MTLBuffer,
        toFragmentParams: MTLBuffer,
        toCameraIndex: MTLBuffer,
        toFreeCameraUniforms: MTLBuffer,
        eye: SIMD3<Float>,
        target: SIMD3<Float>,
        lightPosition: SIMD3<Float>,
        ambientLightColor: SIMD3<Float>,
        upSign: Float32,
        renderViewport: MTLViewport
    ) {
        let viewportWidth = max(renderViewport.width, 1)
        let viewportHeight = max(renderViewport.height, 1)
        let view = lookAt(
            eye: eye,
            target: target,
            up: simd_float3(0, upSign, 0)
        )

        let aspect = Float(viewportWidth / viewportHeight)
        let fovY = Float.pi / 3.0
        let fovX = 2 * atan(tan(fovY / 2) * aspect)
        let projection = perspectiveMatrix(
            fov: fovY,
            aspect: aspect,
            near: 0.1,
            far: 1000.0
        )
        var modelMatrix = matrix_identity_float4x4
        toModelMatrix.contents().copyMemory(
            from: &modelMatrix,
            byteCount: MemoryLayout<float4x4>.size
        )

        var pbrSceneUniforms = SceneUniforms(
            lightPosition: lightPosition,
            ambientLightColor: ambientLightColor,
            viewportSize: SIMD2<Float>(Float(viewportWidth), Float(viewportHeight)),
        )
        toFragmentParams.contents().copyMemory(
            from: &pbrSceneUniforms,
            byteCount: MemoryLayout<SceneUniforms>.size
        )

        var bCameraIndex = cameraIndex ?? -1
        toCameraIndex.contents().copyMemory(
            from: &bCameraIndex,
            byteCount: MemoryLayout<Int>.size
        )

        var freeCameraUniforms = FreeCameraUniforms(
            viewMatrix: view,
            projectionMatrix: projection,
            position: eye,
            fov: SIMD2<Float>(fovX, fovY),
            camRight: SIMD3<Float>(1, 0, 0),
            camUp: SIMD3<Float>(0, 1, 0),
            aspectRatio: aspect
        )
        toFreeCameraUniforms.contents().copyMemory(
            from: &freeCameraUniforms,
            byteCount: MemoryLayout<FreeCameraUniforms>.size
        )
    }

    // MARK: - Rendering

    public override func draw(_ rect: CGRect) {
        guard let drawable = currentDrawable,
              let descriptor = currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }

        let renderViewport = makeRenderViewport(for: drawableSize)

        // Update frame buffer index
        frameSemaphores.wait()
        currentBuffer = (currentBuffer + 1) % maxFramesInFlight

        // Update buffers
        updateSceneBuffer(
            toModelMatrix: modelMatrixBuffer.buffer(currentBuffer),
            toFragmentParams: sceneUniformsBuffer.buffer(currentBuffer),
            toCameraIndex: cameraIndexBuffer.buffer(currentBuffer),
            toFreeCameraUniforms: freeCameraUniformsBuffer.buffer(currentBuffer),
            eye: eye,
            target: freeCameraTarget,
            lightPosition: lightPosition,
            ambientLightColor: ambientLightColor,
            upSign: freeCameraUpSign,
            renderViewport: renderViewport
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
            viewport: renderViewport,
            fragmentParams: sceneUniformsBuffer.buffer(currentBuffer),
            viewPos: eye,
            cameraIndexBuffer: cameraIndexBuffer.buffer(currentBuffer),
            freeCameraUniformsBuffer: freeCameraUniformsBuffer.buffer(currentBuffer),
            modelMatrixBuffer: modelMatrixBuffer.buffer(currentBuffer),
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

    /// Handles scroll wheel input for camera control (macOS).
    ///
    /// With the **Shift** key pressed, pans the camera target in world space.
    /// Otherwise, adjusts the camera angles to orbit the target.
    ///
    /// - Parameter event: The scroll wheel event.
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

    /// Handles trackpad pinch magnification to dolly the camera (macOS).
    ///
    /// Adjusts the camera distance, clamped to a small positive threshold.
    ///
    /// - Parameter event: The magnification gesture event.
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

    private func activeCameraAspectRatio() -> CGFloat? {
        guard let cameraIndex,
              cameraIndex >= 0,
              let gltf = loadedGLTF,
              let cameras = gltf.cameras,
              cameras.indices.contains(cameraIndex) else {
            return nil
        }
        switch cameras[cameraIndex].type {
        case .perspective:
            guard let perspective = cameras[cameraIndex].perspective,
                  let aspect = perspective.aspectRatio,
                  aspect > 0 else {
                return nil
            }
            return CGFloat(aspect)
        case .orthographic:
            guard let orthographic = cameras[cameraIndex].orthographic,
                  orthographic.ymag > 0,
                  orthographic.xmag > 0 else {
                return nil
            }
            return CGFloat(orthographic.xmag / orthographic.ymag)
        }
    }

    private func makeRenderViewport(for size: CGSize) -> MTLViewport {
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        guard let targetAspect = activeCameraAspectRatio(), height > 0 else {
            return MTLViewport(originX: 0, originY: 0, width: width, height: height, znear: 0, zfar: 1)
        }

        let viewAspect = width / height
        let epsilon = 1e-4
        if abs(viewAspect - targetAspect) < epsilon {
            return MTLViewport(originX: 0, originY: 0, width: width, height: height, znear: 0, zfar: 1)
        }

        let clampedAspect = max(targetAspect, epsilon)
        let useWidth = viewAspect > clampedAspect
        let letterboxWidth = useWidth ? height * clampedAspect : width
        let letterboxHeight = useWidth ? height : width / clampedAspect
        let originX = (width - letterboxWidth) * 0.5
        let originY = (height - letterboxHeight) * 0.5
        return MTLViewport(
            originX: originX,
            originY: originY,
            width: letterboxWidth,
            height: letterboxHeight,
            znear: 0,
            zfar: 1
        )
    }

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
