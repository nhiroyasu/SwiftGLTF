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
    @Published var isLoading: Bool = false

    #if os(iOS)
    let allowedContentTypes: [UTType] = [.glb, .vrm]
    #elseif os(macOS)
    let allowedContentTypes: [UTType] = [.gltf, .glb, .vrm]
    #endif

    #if os(iOS)
    let openBuffonTitle = "Open .glb file"
    #elseif os(macOS)
    let openBuffonTitle = "Open .gltf or .glb file"
    #endif

    func loadDefaultAsset() async {
        do {
            let url = Bundle.main.url(forResource: "sphere-with-color", withExtension: "gltf")!
            let asset = try await makeMDLAsset(from: url)
            let newRenderer = try GLTFRenderer()
            try await newRenderer.load(from: asset)
            renderer = newRenderer
        } catch {
            showError = true
            errorMessage = "Failed to load default asset: \(error.localizedDescription)"
        }
    }

    func load(url: URL) async {
        isLoading = true
        defer { isLoading = false }
        guard url.startAccessingSecurityScopedResource() else {
            showError = true
            errorMessage = "Failed to access file at \(url.path)"
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let asset = try await makeMDLAsset(from: url)
            try await self.renderer?.load(from: asset)
        } catch {
            showError = true
            errorMessage = "Failed to load asset: \(error.localizedDescription)"
        }
    }

    func updateRenderingMode(_ mode: RenderingType) async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await renderer?.reload(with: mode)
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
