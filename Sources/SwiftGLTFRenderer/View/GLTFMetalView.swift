import SwiftUI
import MetalKit

#if canImport(UIKit)
import UIKit

public struct GLTFMetalView: UIViewRepresentable {
    let renderer: GLTFRenderer

    public init(renderer: GLTFRenderer) {
        self.renderer = renderer
    }

    public func makeUIView(context: Context) -> GLTFView {
        let view = GLTFView(frame: .zero, renderer: renderer)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }
    public func updateUIView(_ uiView: GLTFView, context: Context) {}
}

#elseif canImport(AppKit)
import AppKit

public struct GLTFMetalView: NSViewRepresentable {
    let renderer: GLTFRenderer

    public init(renderer: GLTFRenderer) {
        self.renderer = renderer
    }

    public func makeNSView(context: Context) -> GLTFView {
        let view = GLTFView(frame: .zero, renderer: renderer)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }
    public func updateNSView(_ nsView: GLTFView, context: Context) {}
}
#endif
