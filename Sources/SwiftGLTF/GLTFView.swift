import SwiftGLTFParser
import SwiftGLTFShaderTypes
import SwiftGLTFRenderer
import SwiftGLTFCore
import MetalKit
import OSLog
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
    private let indirectRenderStateBuilder: PBRIndirectRenderStateBuilder
    private let meshLoader: PBRMeshLoader
    private let envMapLoader: EnvironmentMapLoader

    private var loadedGLTF: GLTF?
    private var loadedMeshBundle: PBRMeshBundle?
    private var loadedIndirectRenderState: PBRIndirectRenderState?
    private var loadedEnvMapBundle: EnvMapBundle?
    public private(set) var vrmHumanoidNodeMap: [VRMHumanoidBoneName: Int] = [:]

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

    // MARK: - VRM
    public var vrmHumanoidRotations: [VRMHumanoidBoneName: SIMD3<Float>] = [:]
    public var vrmExpressionWeights: [VRMExpressionKey: Float] = [:]

    // MARK: - Frame Management
    private let maxFramesInFlight = 2
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
            throw SwiftGLTFError(description: "Failed to create command queue")
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
            depthPixelFormat: depthPixelFormat,
            maxFramesInFlight: maxFramesInFlight
        )
        self.indirectRenderStateBuilder = PBRIndirectRenderStateBuilder(device: device)
        self.meshLoader = try PBRMeshLoader(commandQueue: commandQueue)
        self.envMapLoader = try EnvironmentMapLoader(commandQueue: commandQueue)

        self.frameSemaphores = DispatchSemaphore(value: maxFramesInFlight)

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
    public func load(
        gltf url: URL,
        sceneIndex: Int? = nil,
        animationIndex: Int? = nil,
        variantIndex: Int? = nil
    ) async {
        do {
            displayType = .loading
            defer { displayType = .drawable }
            let data = try Data(contentsOf: url)
            let gltfBundle = try await loadGLTF(from: data, baseURL: url.deletingLastPathComponent())
            let asset = try await makeMDLAsset(from: gltfBundle)
            let meshBundle = try await meshLoader.loadMeshes(
                from: asset,
                sceneIndex: sceneIndex,
                animationIndex: animationIndex,
                variantIndex: variantIndex
            )
            self.loadedMeshBundle = meshBundle
            self.loadedIndirectRenderState = try indirectRenderStateBuilder.build(meshBundle: meshBundle)

            loadedGLTF = gltfBundle.gltf
            vrmHumanoidNodeMap = makeVRMHumanoidNodeMap(from: gltfBundle.gltf)
            updateGLTFDebugHUD()
            updateVRMHumanoidDebugHUD()
            updateVRMExpressionDebugHUD()
            gltfLoadHandler?(.success(gltfBundle.gltf))
        } catch {
            logger.error("Failed to load asset from URL: \(error.localizedDescription, privacy: .public)")
            displayType = .error("Failed to load asset from URL: \(error.localizedDescription)")
            loadedGLTF = nil
            loadedMeshBundle = nil
            vrmHumanoidNodeMap = [:]
            updateGLTFDebugHUD()
            updateVRMHumanoidDebugHUD()
            updateVRMExpressionDebugHUD()
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
    public func load(environment url: URL) async {
        do {
            displayType = .loading
            defer { displayType = .drawable }
            loadedEnvMapBundle = try await envMapLoader.makeEnvMapBundle(from: url)
        } catch {
            logger.error("Failed to load environment map from URL: \(error.localizedDescription, privacy: .public)")
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

    // MARK: - Rendering

    public override func draw(_ rect: CGRect) {
        guard let drawable = currentDrawable,
              let descriptor = currentRenderPassDescriptor,
              let commandBuffer = _makeCommandBuffer(commandQueue),
              let loadedIndirectRenderState else {
            return
        }

        let renderViewport = makeRenderViewport(for: drawableSize)

        // Update frame buffer index
        frameSemaphores.wait()

        // Update animation time
        if let lastTime = lastFrameTime, enabledAnimation {
            let now = CACurrentMediaTime()
            let dt = now - lastTime
            lastFrameTime = now
            animationState.time += Float(dt) * animationState.speed
        } else {
            lastFrameTime = CACurrentMediaTime()
        }

        // Make rendering context
        let context = RenderingContextBuilder
            .new()
            .envMap(bundle: loadedEnvMapBundle)
            .skybox(true)
            .animation(animationState)
            .modelMatrix(matrix_identity_float4x4)
            .lightPosition(lightPosition)
            .ambientLightColor(ambientLightColor)
            .cameraIndex(cameraIndex ?? -1)
            .vrmHumanoidRotations(vrmHumanoidRotations)
            .vrmExpressions(vrmExpressionWeights)
            .freeCameraUniforms(.build(
                eye: eye,
                target: freeCameraTarget,
                upSign: freeCameraUpSign,
                aspect: Float(renderViewport.width / renderViewport.height),
                fovY: .pi / 3
            ))
            .finalizeWithICB(
                state: loadedIndirectRenderState,
                renderPassDescriptor: descriptor,
                drawableSize: drawableSize,
                viewport: renderViewport
            )

        // Render
        renderer.render(commandBuffer: commandBuffer, context: context)

        // Present
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
    private var gltfDebugHUDView: GLTFDebugJSONHUDView?
    private var vrmHumanoidDebugHUDView: VRMHumanoidDebugHUDView?
    private var vrmExpressionDebugHUDView: VRMExpressionDebugHUDView?
    private var debugHUDStackView: UIStackView?

    func setupUI() {
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        self.addGestureRecognizer(panGesture)

        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        self.addGestureRecognizer(pinchGesture)

        messageLabel.isHidden = true
        addSubview(messageLabel)

        if showDebugHUD {
            let scrollView = UIScrollView()
            scrollView.showsVerticalScrollIndicator = true
            scrollView.showsHorizontalScrollIndicator = false
            scrollView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(scrollView)

            let hudStack = UIStackView()
            hudStack.axis = .vertical
            hudStack.alignment = .leading
            hudStack.spacing = 12
            hudStack.translatesAutoresizingMaskIntoConstraints = false
            scrollView.addSubview(hudStack)
            debugHUDStackView = hudStack

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
            hudStack.addArrangedSubview(hud)
            debugHUDView = hud

            let gltfHUD = GLTFDebugJSONHUDView()
            gltfHUD.translatesAutoresizingMaskIntoConstraints = false
            hudStack.addArrangedSubview(gltfHUD)
            gltfDebugHUDView = gltfHUD

            let vrmHUD = VRMHumanoidDebugHUDView()
            vrmHUD.translatesAutoresizingMaskIntoConstraints = false
            vrmHUD.onBoneRotationChange = { [weak self] boneName, rotation in
                self?.vrmHumanoidRotations[boneName] = rotation
            }
            vrmHUD.isHidden = true
            hudStack.addArrangedSubview(vrmHUD)
            vrmHumanoidDebugHUDView = vrmHUD

            let expressionHUD = VRMExpressionDebugHUDView()
            expressionHUD.translatesAutoresizingMaskIntoConstraints = false
            expressionHUD.onExpressionWeightChange = { [weak self] key, weight in
                self?.vrmExpressionWeights[key] = weight
            }
            expressionHUD.isHidden = true
            hudStack.addArrangedSubview(expressionHUD)
            vrmExpressionDebugHUDView = expressionHUD

            let guide = safeAreaLayoutGuide
            NSLayoutConstraint.activate([
                scrollView.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 12),
                scrollView.topAnchor.constraint(equalTo: guide.topAnchor, constant: 12),
                scrollView.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -12),
                scrollView.trailingAnchor.constraint(lessThanOrEqualTo: guide.trailingAnchor, constant: -12),
                hudStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
                hudStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
                hudStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
                hudStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
                hudStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
                hud.widthAnchor.constraint(equalToConstant: 280),
                gltfHUD.widthAnchor.constraint(equalTo: hud.widthAnchor),
                vrmHUD.widthAnchor.constraint(equalTo: hud.widthAnchor),
                expressionHUD.widthAnchor.constraint(equalTo: hud.widthAnchor)
            ])

            hud.update(
                position: eye,
                lightPosition: lightPosition,
                ambientLightColor: ambientLightColor
            )
            updateGLTFDebugHUD()
            updateVRMHumanoidDebugHUD()
            updateVRMExpressionDebugHUD()
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
    private var gltfDebugHUDView: GLTFDebugJSONHUDView?
    private var vrmHumanoidDebugHUDView: VRMHumanoidDebugHUDView?
    private var vrmExpressionDebugHUDView: VRMExpressionDebugHUDView?
    private var debugHUDStackView: NSStackView?

    private final class DebugHUDScrollContentView: NSView {
        override var isFlipped: Bool { true }
    }

    private func setupUI() {
        messageLabel.isEditable = false
        messageLabel.isBezeled = false
        messageLabel.drawsBackground = false
        messageLabel.autoresizingMask = [.width, .height]
        messageLabel.isHidden = true
        addSubview(messageLabel)

        if showDebugHUD {
            let scrollView = NSScrollView()
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = false
            scrollView.drawsBackground = false
            scrollView.borderType = .noBorder
            scrollView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(scrollView)

            let scrollContentView = DebugHUDScrollContentView()
            scrollContentView.translatesAutoresizingMaskIntoConstraints = false
            scrollView.documentView = scrollContentView

            let hudStack = NSStackView()
            hudStack.orientation = .vertical
            hudStack.alignment = .leading
            hudStack.spacing = 12
            hudStack.translatesAutoresizingMaskIntoConstraints = false
            scrollContentView.addSubview(hudStack)
            debugHUDStackView = hudStack

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
            hudStack.addArrangedSubview(hud)
            debugHUDView = hud

            let gltfHUD = GLTFDebugJSONHUDView()
            gltfHUD.translatesAutoresizingMaskIntoConstraints = false
            hudStack.addArrangedSubview(gltfHUD)
            gltfDebugHUDView = gltfHUD

            let vrmHUD = VRMHumanoidDebugHUDView()
            vrmHUD.translatesAutoresizingMaskIntoConstraints = false
            vrmHUD.onBoneRotationChange = { [weak self] boneName, rotation in
                self?.vrmHumanoidRotations[boneName] = rotation
            }
            vrmHUD.isHidden = true
            hudStack.addArrangedSubview(vrmHUD)
            vrmHumanoidDebugHUDView = vrmHUD

            let expressionHUD = VRMExpressionDebugHUDView()
            expressionHUD.translatesAutoresizingMaskIntoConstraints = false
            expressionHUD.onExpressionWeightChange = { [weak self] key, weight in
                self?.vrmExpressionWeights[key] = weight
            }
            expressionHUD.isHidden = true
            hudStack.addArrangedSubview(expressionHUD)
            vrmExpressionDebugHUDView = expressionHUD

            NSLayoutConstraint.activate([
                scrollView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 12),
                scrollView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 12),
                scrollView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -12),
                scrollView.trailingAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.trailingAnchor, constant: -12),
                scrollView.widthAnchor.constraint(equalToConstant: 280),
                scrollContentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
                scrollContentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor),
                hudStack.leadingAnchor.constraint(equalTo: scrollContentView.leadingAnchor),
                hudStack.topAnchor.constraint(equalTo: scrollContentView.topAnchor),
                hudStack.trailingAnchor.constraint(equalTo: scrollContentView.trailingAnchor),
                scrollContentView.bottomAnchor.constraint(greaterThanOrEqualTo: hudStack.bottomAnchor),
                hud.widthAnchor.constraint(equalToConstant: 280),
                gltfHUD.widthAnchor.constraint(equalTo: hud.widthAnchor),
                vrmHUD.widthAnchor.constraint(equalTo: hud.widthAnchor),
                expressionHUD.widthAnchor.constraint(equalTo: hud.widthAnchor)
            ])

            hud.update(
                position: eye,
                lightPosition: lightPosition,
                ambientLightColor: ambientLightColor
            )
            updateGLTFDebugHUD()
            updateVRMHumanoidDebugHUD()
            updateVRMExpressionDebugHUD()
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

    private func updateGLTFDebugHUD() {
        guard showDebugHUD else { return }
        guard let loadedGLTF else {
            gltfDebugHUDView?.update(jsonString: "")
            return
        }
        gltfDebugHUDView?.update(jsonString: makeGLTFDebugJSONString(from: loadedGLTF))
    }

    private func updateVRMHumanoidDebugHUD() {
        guard showDebugHUD else { return }
        guard loadedGLTF?.extensions?.vrmcVrm != nil || loadedGLTF?.extensions?.vrm0?.humanoid != nil else {
            vrmHumanoidDebugHUDView?.isHidden = true
            return
        }
        vrmHumanoidDebugHUDView?.isHidden = false
        vrmHumanoidDebugHUDView?.update(
            availableBones: Set(vrmHumanoidNodeMap.keys),
            rotations: vrmHumanoidRotations
        )
    }

    private func updateVRMExpressionDebugHUD() {
        guard showDebugHUD else { return }
        guard let loadedGLTF else {
            vrmExpressionDebugHUDView?.isHidden = true
            return
        }

        let expressions = makeVRMExpressionKeys(from: loadedGLTF)
        guard !expressions.isEmpty else {
            vrmExpressionDebugHUDView?.isHidden = true
            return
        }

        vrmExpressionDebugHUDView?.isHidden = false
        vrmExpressionDebugHUDView?.update(
            expressions: expressions,
            weights: vrmExpressionWeights
        )
    }

    private func makeVRMExpressionKeys(from gltf: GLTF) -> [VRMExpressionKey] {
        if let expressions = gltf.extensions?.vrmcVrm?.expressions {
            var keys: [VRMExpressionKey] = []
            if let preset = expressions.preset {
                keys.append(contentsOf: makeVRM1PresetExpressionKeys(from: preset))
            }
            if let custom = expressions.custom {
                keys.append(contentsOf: custom.keys.sorted().map { .custom($0) })
            }
            return keys.filter(isDebugVisibleVRMExpressionKey)
        }

        guard let groups = gltf.extensions?.vrm0?.blendShapeMaster?.blendShapeGroups else {
            return []
        }

        return groups
            .compactMap { normalizeVRM0ExpressionKey(from: $0) }
            .filter(isDebugVisibleVRMExpressionKey)
    }

    private func makeVRM1PresetExpressionKeys(from preset: VRMCVrmPresetExpressions) -> [VRMExpressionKey] {
        let expressions: [(VRMExpressionKey, VRMCVrmExpression?)] = [
            (.happy, preset.happy),
            (.angry, preset.angry),
            (.sad, preset.sad),
            (.relaxed, preset.relaxed),
            (.surprised, preset.surprised),
            (.aa, preset.aa),
            (.ih, preset.ih),
            (.ou, preset.ou),
            (.ee, preset.ee),
            (.oh, preset.oh),
            (.blink, preset.blink),
            (.blinkLeft, preset.blinkLeft),
            (.blinkRight, preset.blinkRight),
            (.neutral, preset.neutral)
        ]

        return expressions.compactMap { key, expression in
            expression == nil ? nil : key
        }
    }

    private func isDebugVisibleVRMExpressionKey(_ key: VRMExpressionKey) -> Bool {
        switch key {
        case .lookUp, .lookDown, .lookLeft, .lookRight:
            false
        default:
            true
        }
    }

    private func makeVRMHumanoidNodeMap(from gltf: GLTF) -> [VRMHumanoidBoneName: Int] {
        if let humanBones = gltf.extensions?.vrmcVrm?.humanoid.humanBones {
            return Dictionary(
                uniqueKeysWithValues: VRMHumanoidBoneName.allCases.compactMap { boneName in
                    humanBones.node(for: boneName).map { (boneName, $0.value) }
                }
            )
        }

        guard let nodeMap = gltf.extensions?.vrm0?.humanoid?.nodeMap else {
            return [:]
        }

        return Dictionary(
            uniqueKeysWithValues: VRMHumanoidBoneName.allCases.compactMap { boneName in
                nodeMap[boneName].map { (boneName, $0.value) }
            }
        )
    }

    private func makeGLTFDebugJSONString(from gltf: GLTF) -> String {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(gltf)
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return "Failed to encode glTF JSON: \(error.localizedDescription)"
        }
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

private func _makeCommandBuffer(_ commandQueue: MTLCommandQueue) -> MTLCommandBuffer? {
#if DEBUG
    let desc = MTLCommandBufferDescriptor()
    desc.errorOptions = .encoderExecutionStatus
    let buffer = commandQueue.makeCommandBuffer(descriptor: desc)
    buffer?.label = "[SwiftGLTF] GLTFView Frame Command Buffer"
    buffer?.addCompletedHandler { cb in
        switch cb.status {
        case .error:
            logger.error("[SwiftGLTF] GLTFView: Command buffer completed with error: \(String(describing: cb.error), privacy: .public)")
            if let error = cb.error as? NSError {
                logger.error("[SwiftGLTF] GLTFView: Metal error domain: \(String(describing: error.userInfo[MTLCommandBufferEncoderInfoErrorKey]), privacy: .public)")
            }
        default:
            break
        }
    }
    return buffer
#else
    return commandQueue.makeCommandBuffer()
#endif
}
