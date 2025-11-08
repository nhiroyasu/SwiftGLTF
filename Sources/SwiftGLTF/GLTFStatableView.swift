import SwiftGLTFParser
import SwiftGLTFShaderTypes
import SwiftGLTFRenderer
import SwiftGLTFCore
import MetalKit
import ModelIO
import os.log

/// A subclass of GLTFView that automatically detects changes in the GLTF file and environment map,
/// and reloads only when necessary.
///
///
/// `GLTFStatableView` automatically detects changes when the URL of the GLTF file,
/// the scene index, or the environment map URL are modified,
/// and reloads the content only if there is an actual change.
/// This avoids unnecessary reloads and improves performance.
///
/// ## Usage Example
///
/// ```swift
/// let statableView = try GLTFStatableView(frame: bounds)
///
/// // Simply setting the URL automatically triggers loading
/// statableView.gltfURL = Bundle.main.url(forResource: "model", withExtension: "gltf")
/// statableView.sceneIndex = 0
/// statableView.environmentURL = Bundle.main.url(forResource: "environment", withExtension: "exr")
///
/// // Changing the URL or index automatically triggers reload
/// statableView.gltfURL = newModelURL  // Auto reload
/// statableView.sceneIndex = 1         // Auto reload
/// ```
@MainActor
public class GLTFStatableView: GLTFView {

    // MARK: - Statable Properties

    /// The URL of the currently loaded GLTF file
    private var currentGLTFURL: URL?

    /// The index of the currently loaded scene
    private var currentSceneIndex: Int?

    /// The index of the currently loaded animation
    private var currentAnimationIndex: Int?

    /// The URL of the currently loaded environment map
    private var currentEnvironmentURL: URL?

    // MARK: - Public Interface

    /// The URL of the GLTF file
    ///
    /// When this property is changed, change detection is automatically performed,
    /// and reload is executed only if necessary.
    ///
    /// - Note: Setting the URL to `nil` clears the current state.
    public var gltfURL: URL? {
        didSet {
            if gltfURL != currentGLTFURL {
                reloadGLTFIfNeeded()
            }
        }
    }

    /// The index of the scene to display
    ///
    /// When this property is changed, change detection is automatically performed,
    /// and reload is executed only if necessary.
    ///
    /// - Note: If `nil`, the default scene is used.
    public var sceneIndex: Int? {
        didSet {
            if sceneIndex != currentSceneIndex {
                reloadGLTFIfNeeded()
            }
        }
    }

    /// The index of the animation to play
    ///
    /// When this property is changed, change detection is automatically performed,
    /// and reload is executed only if necessary.
    ///
    /// - Note: If `nil`, no animation is played.
    public var animationIndex: Int? {
        didSet {
            if animationIndex != currentAnimationIndex {
                reloadGLTFIfNeeded()
            }
        }
    }

    /// The URL of the environment map
    ///
    /// When this property is changed, change detection is automatically performed,
    /// and the environment map is reloaded only if it has changed.
    ///
    /// - Note: Setting the URL to `nil` clears the environment map.
    public var environmentURL: URL? {
        didSet {
            if environmentURL != currentEnvironmentURL {
                reloadEnvironmentIfNeeded()
            }
        }
    }

    // MARK: - Initialization

    /// Initializer for GLTFStatableView
    ///
    /// - Parameters:
    ///   - frame: The frame of the view
    ///   - device: The Metal device to use. Default is the system default device.
    ///   - showDebugHUD: Flag to show debug HUD. Default is `false`.
    /// - Throws: Throws if Metal device initialization or renderer creation fails.
    public override init(
        frame: CGRect,
        device: MTLDevice = MTLCreateSystemDefaultDevice()!,
        showDebugHUD: Bool = false
    ) throws {
        try super.init(frame: frame, device: device, showDebugHUD: showDebugHUD)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Private Methods

    /// Checks if reloading the GLTF is necessary and performs it if needed.
    ///
    /// Reloads when the URL or scene index changes.
    /// Compares the contents of the GLTF file and reloads only if there is an actual change.
    private func reloadGLTFIfNeeded() {
        guard let url = gltfURL else {
            currentGLTFURL = nil
            currentSceneIndex = nil
            currentAnimationIndex = nil
            return
        }

        let needsReload = url != currentGLTFURL || sceneIndex != currentSceneIndex || animationIndex != currentAnimationIndex
        guard needsReload else { return }
        currentGLTFURL = url
        currentSceneIndex = sceneIndex
        currentAnimationIndex = animationIndex

        super.load(gltf: url, sceneIndex: sceneIndex, animationIndex: animationIndex)
        os_log("GLTFStatableView: Reloaded GLTF due to asset change", type: .info)
    }

    /// Checks if reloading the environment map is necessary and performs it if needed.
    ///
    /// Reloads when the environment map URL changes.
    private func reloadEnvironmentIfNeeded() {
        guard let url = environmentURL else {
            currentEnvironmentURL = nil
            return
        }

        if url != currentEnvironmentURL {
            currentEnvironmentURL = url
            super.load(environment: url)
            os_log("GLTFStatableView: Reloaded environment map", type: .info)
        }
    }

    // MARK: - Public Override Methods

    /// Loads a GLTF file directly
    ///
    /// This method updates the internal state before calling the superclass load method.
    ///
    /// - Parameters:
    ///   - url: The URL of the GLTF file to load
    ///   - sceneIndex: The index of the scene to display. If `nil`, the default scene is used.
    public override func load(gltf url: URL, sceneIndex: Int?, animationIndex: Int?) {
        currentGLTFURL = url
        currentSceneIndex = sceneIndex
        currentAnimationIndex = animationIndex
        reloadGLTFIfNeeded()
    }

    /// Loads an environment map directly
    ///
    /// This method updates the internal state before calling the superclass load method.
    ///
    /// - Parameter url: The URL of the environment map to load
    public override func load(environment url: URL) {
        currentEnvironmentURL = url
        reloadEnvironmentIfNeeded()
    }
}
