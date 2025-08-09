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

    public init(url: URL, automaticallyAccessSecurityScope: Bool = true) {
        self.dataType = .url(url, automaticallyAccessSecurityScope)
    }

    public func makeUIView(context: Context) -> GLTFView {
        if let view = try? GLTFView(frame: .zero) {
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
                await uiView.load(from: url)
                if shouldStoppedAccessingSecurityScopedResource {
                    url.stopAccessingSecurityScopedResource()
                }
            case .asset(let mdlAsset):
                await uiView.load(from: mdlAsset)
            }
        }
    }
}

#elseif canImport(AppKit)
import AppKit

public struct GLTFMetalView: NSViewRepresentable {
    private let dataType: GLTFMetalViewDataType

    public init(url: URL, automaticallyAccessSecurityScope: Bool = true) {
        self.dataType = .url(url, automaticallyAccessSecurityScope)
    }

    public func makeNSView(context: Context) -> GLTFView {
        if let view = try? GLTFView(frame: .zero) {
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
                await nsView.load(from: url)
                if shouldStoppedAccessingSecurityScopedResource {
                    url.stopAccessingSecurityScopedResource()
                }
            case .asset(let mdlAsset):
                await nsView.load(from: mdlAsset)
            }
        }
    }
}
#endif
