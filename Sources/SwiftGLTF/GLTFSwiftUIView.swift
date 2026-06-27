import SwiftUI
import MetalKit
import SwiftGLTFCore
import simd

#if canImport(UIKit)
import UIKit

public struct GLTFSwiftUIView: UIViewRepresentable {
    private let url: URL
    private let sceneIndex: Int?
    private let animationIndex: Int?
    private let variantIndex: Int?
    private let cameraIndex: Int?
    private let vrmHumanoidRotations: [VRMHumanoidBoneName: SIMD3<Float>]
    private let vrmExpressionWeights: [VRMExpressionKey: Float]
    private let environmentUrl: URL?
    private let modelBinding: Binding<GLTF?>?
    private let showDebugHUD: Bool
    private let automaticallyAccessSecurityScope: Bool

    public init(
        url: URL,
        sceneIndex: Int? = nil,
        animationIndex: Int? = nil,
        variantIndex: Int? = nil,
        cameraIndex: Int? = nil,
        vrmHumanoidRotations: [VRMHumanoidBoneName: SIMD3<Float>] = [:],
        vrmExpressionWeights: [VRMExpressionKey: Float] = [:],
        environmentUrl: URL? = nil,
        modelBinding: Binding<GLTF?>? = nil,
        showDebugHUD: Bool = false,
        automaticallyAccessSecurityScope: Bool = true
    ) {
        self.url = url
        self.sceneIndex = sceneIndex
        self.animationIndex = animationIndex
        self.variantIndex = variantIndex
        self.cameraIndex = cameraIndex
        self.vrmHumanoidRotations = vrmHumanoidRotations
        self.vrmExpressionWeights = vrmExpressionWeights
        self.environmentUrl = environmentUrl
        self.modelBinding = modelBinding
        self.showDebugHUD = showDebugHUD
        self.automaticallyAccessSecurityScope = automaticallyAccessSecurityScope
    }

    public func makeUIView(context: Context) -> GLTFStatableView {
        if let view = try? GLTFStatableView(frame: .zero, showDebugHUD: showDebugHUD) {
            view.translatesAutoresizingMaskIntoConstraints = false
            return view
        } else {
            fatalError("Failed to create GLTFView")
        }
    }

    public func updateUIView(_ uiView: GLTFStatableView, context: Context) {
        let shouldStoppedAccessingSecurityScopedResource = automaticallyAccessSecurityScope && url.startAccessingSecurityScopedResource()
        uiView.gltfURL = url
        uiView.sceneIndex = sceneIndex
        uiView.animationIndex = animationIndex
        uiView.cameraIndex = cameraIndex
        uiView.vrmHumanoidRotations = vrmHumanoidRotations
        uiView.vrmExpressionWeights = vrmExpressionWeights
        uiView.variantIndex = variantIndex
        uiView.environmentURL = environmentUrl
        uiView.gltfLoadHandler = { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let gltf):
                    modelBinding?.wrappedValue = gltf
                case .failure:
                    modelBinding?.wrappedValue = nil
                }
            }
        }
        if shouldStoppedAccessingSecurityScopedResource {
            url.stopAccessingSecurityScopedResource()
        }
    }
}

#elseif canImport(AppKit)
import AppKit

public struct GLTFSwiftUIView: NSViewRepresentable {
    private let url: URL
    private let sceneIndex: Int?
    private let animationIndex: Int?
    private let variantIndex: Int?
    private let cameraIndex: Int?
    private let vrmHumanoidRotations: [VRMHumanoidBoneName: SIMD3<Float>]
    private let vrmExpressionWeights: [VRMExpressionKey: Float]
    private let environmentUrl: URL?
    private let modelBinding: Binding<GLTF?>?
    private let showDebugHUD: Bool
    private let automaticallyAccessSecurityScope: Bool

    public var gltfLoadHandler: ((Result<GLTF, Error>) -> Void)?

    public init(
        url: URL,
        sceneIndex: Int? = nil,
        animationIndex: Int? = nil,
        variantIndex: Int? = nil,
        cameraIndex: Int? = nil,
        vrmHumanoidRotations: [VRMHumanoidBoneName: SIMD3<Float>] = [:],
        vrmExpressionWeights: [VRMExpressionKey: Float] = [:],
        environmentUrl: URL? = nil,
        modelBinding: Binding<GLTF?>? = nil,
        showDebugHUD: Bool = false,
        automaticallyAccessSecurityScope: Bool = true
    ) {
        self.url = url
        self.sceneIndex = sceneIndex
        self.animationIndex = animationIndex
        self.variantIndex = variantIndex
        self.cameraIndex = cameraIndex
        self.vrmHumanoidRotations = vrmHumanoidRotations
        self.vrmExpressionWeights = vrmExpressionWeights
        self.environmentUrl = environmentUrl
        self.modelBinding = modelBinding
        self.showDebugHUD = showDebugHUD
        self.automaticallyAccessSecurityScope = automaticallyAccessSecurityScope
    }

    public func makeNSView(context: Context) -> GLTFStatableView {
        do {
            let view = try GLTFStatableView(frame: .zero, showDebugHUD: showDebugHUD)
            view.translatesAutoresizingMaskIntoConstraints = false
            return view
        } catch {
            fatalError("Failed to create GLTFView: \(error)")
        }
    }

    public func updateNSView(_ nsView: GLTFStatableView, context: Context) {
        let shouldStoppedAccessingSecurityScopedResource = automaticallyAccessSecurityScope && url.startAccessingSecurityScopedResource()
        nsView.gltfURL = url
        nsView.sceneIndex = sceneIndex
        nsView.animationIndex = animationIndex
        nsView.cameraIndex = cameraIndex
        nsView.vrmHumanoidRotations = vrmHumanoidRotations
        nsView.vrmExpressionWeights = vrmExpressionWeights
        nsView.variantIndex = variantIndex
        nsView.environmentURL = environmentUrl
        nsView.gltfLoadHandler = { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let gltf):
                    modelBinding?.wrappedValue = gltf
                case .failure:
                    modelBinding?.wrappedValue = nil
                }
            }
        }
        if shouldStoppedAccessingSecurityScopedResource {
            url.stopAccessingSecurityScopedResource()
        }
    }
}
#endif
