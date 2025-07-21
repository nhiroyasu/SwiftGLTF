import Foundation
import SwiftUI
import SwiftGLTF
import SwiftGLTFRenderer
import ModelIO
import UniformTypeIdentifiers

@MainActor
class GLTFViewModel: ObservableObject, DropDelegate {
    @Published var renderer: GLTFRenderer?
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var showFileImporter = false
    @Published var mode: RenderingType = .pbr

    #if os(iOS)
    let allowedContentTypes: [UTType] = [.glb, .vrm]
    #elseif os(macOS)
    let allowedContentTypes: [UTType] = [.gltf, .glb, .vrm]
    #endif

    func loadDefaultAsset() async {
        do {
            let url = Bundle.main.url(forResource: "sphere-with-color", withExtension: "gltf")!
            let asset = try makeMDLAsset(from: url)
            let newRenderer = try await GLTFRenderer()
            try newRenderer.load(from: asset)
            renderer = newRenderer
        } catch {
            showError = true
            errorMessage = "Failed to load default asset: \(error.localizedDescription)"
        }
    }

    func load(url: URL) async {
        guard url.startAccessingSecurityScopedResource() else {
            showError = true
            errorMessage = "Failed to access file at \(url.path)"
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let asset = try makeMDLAsset(from: url)
            try renderer?.load(from: asset)
        } catch {
            showError = true
            errorMessage = "Failed to load asset: \(error.localizedDescription)"
        }
    }

    func updateRenderingMode(_ mode: RenderingType) {
        do {
            try renderer?.reload(with: mode)
        } catch {
            showError = true
            errorMessage = "Failed to update rendering mode: \(error.localizedDescription)"
        }
    }

    func onTapOpenFile() {
        showFileImporter = true
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: allowedContentTypes)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let itemProvider = info.itemProviders(for: allowedContentTypes).first else {
            return false
        }

        Task {
            var obj: NSSecureCoding?
            for type in allowedContentTypes {
                obj = try? await itemProvider.loadItem(forTypeIdentifier: type.identifier)
                if obj != nil {
                    break
                }
            }
            guard let url = obj as? URL else {
                showError = true
                errorMessage = "Unsupported file type"
                return
            }
            guard url.startAccessingSecurityScopedResource() else {
                showError = true
                errorMessage = "Failed to access file at \(url.path)"
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            await load(url: url)
        }
        return true
    }
}
