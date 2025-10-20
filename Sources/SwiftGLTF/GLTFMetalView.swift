import SwiftUI
import MetalKit

enum GLTFMetalViewDataType {
    case url(URL, Bool)
    case asset(MDLAsset)
}

#if canImport(UIKit)
import UIKit

public struct GLTFMetalView: UIViewRepresentable {
    private let dataType: GLTFMetalViewDataType
    private let sceneIndex: Int?
    private let showDebugHUD: Bool

    public init(
        url: URL,
        sceneIndex: Int? = nil,
        automaticallyAccessSecurityScope: Bool = true,
        showDebugHUD: Bool = false
    ) {
        self.dataType = .url(url, automaticallyAccessSecurityScope)
        self.sceneIndex = sceneIndex
        self.showDebugHUD = showDebugHUD
    }

    public init(
        asset: MDLAsset,
        sceneIndex: Int? = nil,
        showDebugHUD: Bool = false
    ) {
        self.dataType = .asset(asset)
        self.sceneIndex = sceneIndex
        self.showDebugHUD = showDebugHUD
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
            switch dataType {
            case .url(let url, let automaticallyAccessSecurityScope):
                let shouldStoppedAccessingSecurityScopedResource = automaticallyAccessSecurityScope && url.startAccessingSecurityScopedResource()
                await uiView.load(from: url, sceneIndex: sceneIndex)
                if shouldStoppedAccessingSecurityScopedResource {
                    url.stopAccessingSecurityScopedResource()
                }
            case .asset(let mdlAsset):
                await uiView.load(from: mdlAsset, sceneIndex: sceneIndex)
            }
        }
    }
}

#elseif canImport(AppKit)
import AppKit

public struct GLTFMetalView: NSViewRepresentable {
    private let dataType: GLTFMetalViewDataType
    private let sceneIndex: Int?
    private let showDebugHUD: Bool

    public init(
        url: URL,
        sceneIndex: Int? = nil,
        automaticallyAccessSecurityScope: Bool = true,
        showDebugHUD: Bool = false
    ) {
        self.dataType = .url(url, automaticallyAccessSecurityScope)
        self.sceneIndex = sceneIndex
        self.showDebugHUD = showDebugHUD
    }

    public init(
        asset: MDLAsset,
        sceneIndex: Int? = nil,
        showDebugHUD: Bool = false
    ) {
        self.dataType = .asset(asset)
        self.sceneIndex = sceneIndex
        self.showDebugHUD = showDebugHUD
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
            switch dataType {
            case .url(let url, let automaticallyAccessSecurityScope):
                let shouldStoppedAccessingSecurityScopedResource = automaticallyAccessSecurityScope && url.startAccessingSecurityScopedResource()
                await nsView.load(from: url, sceneIndex: sceneIndex)
                if shouldStoppedAccessingSecurityScopedResource {
                    url.stopAccessingSecurityScopedResource()
                }
            case .asset(let mdlAsset):
                await nsView.load(from: mdlAsset, sceneIndex: sceneIndex)
            }
        }
    }
}
#endif
