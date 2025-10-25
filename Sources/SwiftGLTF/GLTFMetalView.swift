import SwiftUI
import MetalKit
import SwiftGLTFCore

#if canImport(UIKit)
import UIKit

public struct GLTFMetalView: UIViewRepresentable {
    private let url: URL
    private let sceneIndex: Int?
    private let environmentUrl: URL?
    private let showDebugHUD: Bool
    private let automaticallyAccessSecurityScope: Bool
    private let gltfViewDelegate: GLTFViewDelegateWrap = .init()

    public init(
        url: URL,
        sceneIndex: Int? = nil,
        environmentUrl: URL? = nil,
        showDebugHUD: Bool = false,
        automaticallyAccessSecurityScope: Bool = true
    ) {
        self.url = url
        self.sceneIndex = sceneIndex
        self.environmentUrl = environmentUrl
        self.showDebugHUD = showDebugHUD
        self.automaticallyAccessSecurityScope = automaticallyAccessSecurityScope
    }

    public func makeUIView(context: Context) -> GLTFStableView {
        if let view = try? GLTFStableView(frame: .zero, showDebugHUD: showDebugHUD) {
            view.gltfDelegate = gltfViewDelegate
            view.translatesAutoresizingMaskIntoConstraints = false
            return view
        } else {
            fatalError("Failed to create GLTFView")
        }
    }

    public func updateUIView(_ uiView: GLTFStableView, context: Context) {
        Task {
            let shouldStoppedAccessingSecurityScopedResource = automaticallyAccessSecurityScope && url.startAccessingSecurityScopedResource()
            uiView.gltfURL = url
            uiView.environmentURL = environmentUrl
            if shouldStoppedAccessingSecurityScopedResource {
                url.stopAccessingSecurityScopedResource()
            }
        }
    }

    public func onGLTFLoaded(
        _ handler: @escaping (GLTF?, (any Error)?) -> Void
    ) -> GLTFMetalView {
        gltfViewDelegate.loadedHandler = handler
        return self
    }
}

#elseif canImport(AppKit)
import AppKit

public struct GLTFMetalView: NSViewRepresentable {
    private let url: URL
    private let sceneIndex: Int?
    private let environmentUrl: URL?
    private let showDebugHUD: Bool
    private let automaticallyAccessSecurityScope: Bool
    private let gltfViewDelegate: GLTFViewDelegateWrap = .init()

    public init(
        url: URL,
        sceneIndex: Int? = nil,
        environmentUrl: URL? = nil,
        showDebugHUD: Bool = false,
        automaticallyAccessSecurityScope: Bool = true,
    ) {
        self.url = url
        self.sceneIndex = sceneIndex
        self.environmentUrl = environmentUrl
        self.showDebugHUD = showDebugHUD
        self.automaticallyAccessSecurityScope = automaticallyAccessSecurityScope
    }

    public func makeNSView(context: Context) -> GLTFStableView {
        if let view = try? GLTFStableView(frame: .zero, showDebugHUD: showDebugHUD) {
            view.gltfDelegate = gltfViewDelegate
            view.translatesAutoresizingMaskIntoConstraints = false
            return view
        } else {
            fatalError("Failed to create GLTFView")
        }
    }

    public func updateNSView(_ nsView: GLTFStableView, context: Context) {
        let shouldStoppedAccessingSecurityScopedResource = automaticallyAccessSecurityScope && url.startAccessingSecurityScopedResource()
        nsView.gltfURL = url
        nsView.environmentURL = environmentUrl
        if shouldStoppedAccessingSecurityScopedResource {
            url.stopAccessingSecurityScopedResource()
        }
    }

    public func onGLTFLoaded(
        _ handler: @escaping (GLTF?, (any Error)?) -> Void
    ) -> GLTFMetalView {
        gltfViewDelegate.loadedHandler = handler
        return self
    }
}
#endif

private class GLTFViewDelegateWrap: GLTFViewDelegate {
    var loadedHandler: ((GLTF?, (any Error)?) -> Void)?

    func loaded(gltf: GLTF?, error: (any Error)?) {
        loadedHandler?(gltf, error)
    }
}
