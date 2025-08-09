import Foundation
import SwiftUI
import SwiftGLTFRenderer
import ModelIO
import UniformTypeIdentifiers

@MainActor
class GLTFViewModel: ObservableObject, DropDelegate {
    @Published var url: URL?
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var showFileImporter = false
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

    func loadDefaultAsset() {
        url = Bundle.main.url(forResource: "sphere-with-color", withExtension: "gltf")!
    }

    func load(url: URL) {
        self.url = url
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
            self.url = url
        }
        return true
    }
}
