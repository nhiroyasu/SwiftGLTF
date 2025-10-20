import SwiftUI
import MetalKit

#if canImport(UIKit)
import UIKit

public struct GLTFMetalView: UIViewRepresentable {
    private let url: URL
    private let sceneIndex: Int?
    private let environmentUrl: URL?
    private let showDebugHUD: Bool
    private let automaticallyAccessSecurityScope: Bool

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

    public func makeUIView(context: Context) -> GLTFView {
        if let view = try? GLTFView(frame: .zero, showDebugHUD: showDebugHUD) {
            view.translatesAutoresizingMaskIntoConstraints = false
            return view
        } else {
            fatalError("Failed to create GLTFView")
        }
    }

    public func updateUIView(_ uiView: GLTFView, context: Context) {
        Task {
            let shouldStoppedAccessingSecurityScopedResource = automaticallyAccessSecurityScope && url.startAccessingSecurityScopedResource()
            await uiView.load(gltf: url, sceneIndex: sceneIndex)
            if let environmentUrl {
                await uiView.load(environment: environmentUrl)
            }
            if shouldStoppedAccessingSecurityScopedResource {
                url.stopAccessingSecurityScopedResource()
            }
        }
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

    public func makeNSView(context: Context) -> GLTFView {
        if let view = try? GLTFView(frame: .zero, showDebugHUD: showDebugHUD) {
            view.translatesAutoresizingMaskIntoConstraints = false
            return view
        } else {
            fatalError("Failed to create GLTFView")
        }
    }

    public func updateNSView(_ nsView: GLTFView, context: Context) {
        Task {
            let shouldStoppedAccessingSecurityScopedResource = automaticallyAccessSecurityScope && url.startAccessingSecurityScopedResource()
            await nsView.load(gltf: url, sceneIndex: sceneIndex)
            if let environmentUrl {
                await nsView.load(environment: environmentUrl)
            }
            if shouldStoppedAccessingSecurityScopedResource {
                url.stopAccessingSecurityScopedResource()
            }
        }
    }
}
#endif
