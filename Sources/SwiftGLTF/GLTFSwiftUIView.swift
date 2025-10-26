import SwiftUI
import MetalKit
import SwiftGLTFCore

#if canImport(UIKit)
import UIKit

public struct GLTFSwiftUIView: UIViewRepresentable {
    private let url: URL
    private let sceneIndex: Int?
    private let environmentUrl: URL?
    private let modelBinding: Binding<GLTF?>?
    private let showDebugHUD: Bool
    private let automaticallyAccessSecurityScope: Bool

    public init(
        url: URL,
        sceneIndex: Int? = nil,
        environmentUrl: URL? = nil,
        modelBinding: Binding<GLTF?>? = nil,
        showDebugHUD: Bool = false,
        automaticallyAccessSecurityScope: Bool = true
    ) {
        self.url = url
        self.sceneIndex = sceneIndex
        self.environmentUrl = environmentUrl
        self.modelBinding = modelBinding
        self.showDebugHUD = showDebugHUD
        self.automaticallyAccessSecurityScope = automaticallyAccessSecurityScope
    }

    public func makeUIView(context: Context) -> GLTFStableView {
        if let view = try? GLTFStableView(frame: .zero, showDebugHUD: showDebugHUD) {
            view.translatesAutoresizingMaskIntoConstraints = false
            return view
        } else {
            fatalError("Failed to create GLTFView")
        }
    }

    public func updateUIView(_ uiView: GLTFStableView, context: Context) {
        let shouldStoppedAccessingSecurityScopedResource = automaticallyAccessSecurityScope && url.startAccessingSecurityScopedResource()
        uiView.gltfURL = url
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
    private let environmentUrl: URL?
    private let modelBinding: Binding<GLTF?>?
    private let showDebugHUD: Bool
    private let automaticallyAccessSecurityScope: Bool

    public var gltfLoadHandler: ((Result<GLTF, Error>) -> Void)?

    public init(
        url: URL,
        sceneIndex: Int? = nil,
        environmentUrl: URL? = nil,
        modelBinding: Binding<GLTF?>? = nil,
        showDebugHUD: Bool = false,
        automaticallyAccessSecurityScope: Bool = true
    ) {
        self.url = url
        self.sceneIndex = sceneIndex
        self.environmentUrl = environmentUrl
        self.modelBinding = modelBinding
        self.showDebugHUD = showDebugHUD
        self.automaticallyAccessSecurityScope = automaticallyAccessSecurityScope
    }

    public func makeNSView(context: Context) -> GLTFStableView {
        if let view = try? GLTFStableView(frame: .zero, showDebugHUD: showDebugHUD) {
            view.translatesAutoresizingMaskIntoConstraints = false
            return view
        } else {
            fatalError("Failed to create GLTFView")
        }
    }

    public func updateNSView(_ nsView: GLTFStableView, context: Context) {
        let shouldStoppedAccessingSecurityScopedResource = automaticallyAccessSecurityScope && url.startAccessingSecurityScopedResource()
        nsView.gltfURL = url
        nsView.sceneIndex = sceneIndex
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
