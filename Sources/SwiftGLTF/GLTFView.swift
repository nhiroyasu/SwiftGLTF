import SwiftGLTFParser
import SwiftGLTFShaderTypes
import SwiftGLTFRenderer
import MetalKit
import OSLog

@MainActor
public class GLTFView: MTKView {
    private let commandQueue: MTLCommandQueue

    private let renderer: PBRRenderer

    private let fragmentParamsBuffer: FrameInFlightBuffer
    private let vertexPramsBuffer: FrameInFlightBuffer
    private let skyboxVPMatrixBuffer: FrameInFlightBuffer

    private var displayType: DisplayType = .loading {
        didSet { onChange(displayType) }
    }
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

    public init(
        frame: CGRect,
        asset: MDLAsset? = nil,
        environmentMapURL: URL? = nil,
        device: MTLDevice = MTLCreateSystemDefaultDevice()!
    ) throws {
        let device = device
        if let commandQueue = device.makeCommandQueue() {
            self.commandQueue = commandQueue
        } else {
            throw NSError(domain: "PBRRenderer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create command queue"])
        }

        let sampleCount = 4
        let colorPixelFormat: MTLPixelFormat = .rgba8Unorm_srgb
        let depthPixelFormat: MTLPixelFormat = .depth32Float

        self.renderer = try PBRRenderer(
            commandQueue: commandQueue,
            sampleCount: sampleCount,
            colorPixelFormat: colorPixelFormat,
            depthPixelFormat: depthPixelFormat
        )

        self.frameSemaphores = DispatchSemaphore(value: maxFramesInFlight)

        self.fragmentParamsBuffer = FrameInFlightBuffer(maxFramesInFlight: maxFramesInFlight) {
            device.makeBuffer(
                length: MemoryLayout<PBRFragmentVariableParameters>.size,
                options: []
            )!
        }
        self.vertexPramsBuffer = FrameInFlightBuffer(maxFramesInFlight: maxFramesInFlight) {
            device.makeBuffer(
                length: MemoryLayout<PBRVertexVariableParameters>.size,
                options: .storageModeShared
            )!
        }
        self.skyboxVPMatrixBuffer = FrameInFlightBuffer(maxFramesInFlight: maxFramesInFlight) {
            device.makeBuffer(
                length: MemoryLayout<simd_float4x4>.size,
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

        Task {
            let url = environmentMapURL ?? Bundle.module.url(forResource: "env_map", withExtension: "exr")!
            try await renderer.setEnvironment(url: url)
            if let asset {
                await load(from: asset)
            }
        }
    }

    public convenience init(
        frame: CGRect,
        url: URL,
        device: MTLDevice = MTLCreateSystemDefaultDevice()!
    ) throws {
        try self.init(frame: frame, device: device)

        Task {
            let asset = try await makeMDLAsset(from: url)
            await self.load(from: asset)
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - State Management

    public func load(from asset: MDLAsset) async {
        do {
            displayType = .loading
            try await renderer.load(from: asset)
            displayType = .drawable
        } catch {
            os_log("Failed to load asset: %@", type: .error, error.localizedDescription)
            displayType = .error("Failed to load asset: \(error.localizedDescription)")
        }
    }

    public func loadAsync(from asset: MDLAsset) {
        Task {
            do {
                displayType = .loading
                try await renderer.load(from: asset)
                displayType = .drawable
            } catch {
                os_log("Failed to load asset: %@", type: .error, error.localizedDescription)
                displayType = .error("Failed to load asset: \(error.localizedDescription)")
            }
        }
    }

    public func load(from url: URL) async {
        do {
            displayType = .loading
            let asset = try await makeMDLAsset(from: url)
            await load(from: asset)
        } catch {
            os_log("Failed to load asset from URL: %@", type: .error, error.localizedDescription)
            displayType = .error("Failed to load asset from URL: \(error.localizedDescription)")
        }
    }

    public func loadAsync(from url: URL) {
        Task {
            do {
                displayType = .loading
                let asset = try await makeMDLAsset(from: url)
                await load(from: asset)
            } catch {
                os_log("Failed to load asset from URL: %@", type: .error, error.localizedDescription)
                displayType = .error("Failed to load asset from URL: \(error.localizedDescription)")
            }
        }
    }

    public func resetCamera() {
        rotationX = -.pi / 2
        rotationY = .pi / 2
        upSign = 1
        distance = 5
        targetOffset = .zero
    }

    // MARK: - Buffer Management

    private func updateSkyboxBuffer(
        toVPMatrix: MTLBuffer,
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
        toVPMatrix.contents().copyMemory(
            from: &skyboxVPMatrix,
            byteCount: MemoryLayout<simd_float4x4>.size
        )
    }

    private func updateSceneBuffer(
        toVertexParams: MTLBuffer,
        toFragmentParams: MTLBuffer,
        eye: SIMD3<Float>,
        lightPosition: SIMD3<Float>,
        ambientLightColor: SIMD3<Float>,
        upSign: Float32,
        drawableSize: CGSize
    ) {
        let view = lookAt(
            eye: eye,
            target: simd_float3(0, 0, 0),
            up: simd_float3(0, upSign, 0)
        )
        let projection = perspectiveMatrix(
            fov: .pi / 3,
            aspect: Float(drawableSize.width / drawableSize.height),
            near: 0.1,
            far: 1000.0
        )
        let offset = translationMatrix(targetOffset.x, targetOffset.y, targetOffset.z)
        var vpUniforms = PBRVertexVariableParameters(
            view: view,
            projection: projection,
            externalTransform: offset
        )
        toVertexParams.contents().copyMemory(
            from: &vpUniforms,
            byteCount: MemoryLayout<PBRVertexVariableParameters>.size
        )

        var pbrSceneUniforms = PBRFragmentVariableParameters(
            lightPosition: lightPosition,
            viewPosition: eye,
            ambientLightColor: ambientLightColor
        )
        toFragmentParams.contents().copyMemory(
            from: &pbrSceneUniforms,
            byteCount: MemoryLayout<PBRFragmentVariableParameters>.size
        )
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

        // Update buffers
        updateSkyboxBuffer(
            toVPMatrix: skyboxVPMatrixBuffer.buffer(currentBuffer),
            rotationX: rotationX,
            rotationY: rotationY,
            upSign: upSign,
            drawableSize: drawableSize
        )
        updateSceneBuffer(
            toVertexParams: vertexPramsBuffer.buffer(currentBuffer),
            toFragmentParams: fragmentParamsBuffer.buffer(currentBuffer),
            eye: eye,
            lightPosition: lightPosition,
            ambientLightColor: ambientLightColor,
            upSign: upSign,
            drawableSize: drawableSize
        )

        // Rendering
        renderer.render(
            using: renderEncoder,
            vertexParams: vertexPramsBuffer.buffer(currentBuffer),
            fragmentParams: fragmentParamsBuffer.buffer(currentBuffer),
            skyboxVP: skyboxVPMatrixBuffer.buffer(currentBuffer)
        )

        // Finalize rendering

        renderEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.addCompletedHandler { [weak frameSemaphores] _ in
            frameSemaphores?.signal()
        }
        commandBuffer.commit()
    }

    // MARK: - UI

    #if os(iOS)
    private let messageLabel = UILabel()

    func setupUI() {
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        self.addGestureRecognizer(panGesture)

        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        self.addGestureRecognizer(pinchGesture)

        messageLabel.isHidden = true
        addSubview(messageLabel)
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

    func showError(_ message: String) {
        messageLabel.text = message
        messageLabel.textColor = .systemRed
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }

    #elseif os(macOS)

    private let messageLabel = NSTextField()

    private func setupUI() {
        messageLabel.isEditable = false
        messageLabel.isBezeled = false
        messageLabel.drawsBackground = false
        messageLabel.autoresizingMask = [.width, .height]
        messageLabel.isHidden = true
        addSubview(messageLabel)
    }

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

    func showError(_ message: String) {
        messageLabel.stringValue = message
        messageLabel.textColor = .systemRed
        messageLabel.alignment = .center
    }

    #endif

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
