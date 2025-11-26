import Foundation
import SwiftUI
import ModelIO
import UniformTypeIdentifiers
import SwiftGLTF
import SwiftGLTFCore

@MainActor
class GLTFViewModel: ObservableObject, DropDelegate {
    @Published var url: URL?
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var showFileImporter = false
    @Published var isLoading: Bool = false
    @Published var selectedSceneIndex: Int? = nil
    @Published var selectedAnimationIndex: Int? = nil
    @Published var selectedCameraIndex: Int? = nil
    @Published var selectedVariantIndex: Int? = nil
    @Published var gltf: GLTF?

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
        do {
            try checkSwiftGLTFMTKDeviceSupported(device: MTLCreateSystemDefaultDevice()!)
            url = Bundle.main.url(forResource: "sphere-with-color", withExtension: "gltf")!
        } catch {
            showError = true
            errorMessage = "\(error)"
        }
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

    var sceneIndex: Int? {
        if let scenes = gltf?.scenes, let selectedSceneIndex {
            return min(max(selectedSceneIndex, 0), scenes.count - 1)
        } else {
            return nil
        }
    }

    var sceneCount: Int {
        gltf?.scenes?.count ?? 1
    }

    var sceneMenuLabel: String {
        if let selectedSceneIndex {
            return "Scene: \(selectedSceneIndex)"
        } else {
            return "Scene: Default"
        }
    }

    var animationIndex: Int? {
        if let animations = gltf?.animations, let selectedAnimationIndex {
            return min(max(selectedAnimationIndex, 0), animations.count - 1)
        } else {
            return nil
        }
    }

    var animationCount: Int {
        gltf?.animations?.count ?? 0
    }

    var animationMenuLabel: String {
        if let selectedAnimationIndex {
            return "Animation: \(selectedAnimationIndex)"
        } else {
            if let anim = gltf?.animations, !anim.isEmpty {
                return "Animation: Default"
            } else {
                return "Animation: None"
            }
        }
    }

    var cameraIndex: Int? {
        if let cameras = gltf?.cameras, let selectedCameraIndex {
            return min(max(selectedCameraIndex, 0), cameras.count - 1)
        } else {
            return nil
        }
    }

    var cameraCount: Int {
        gltf?.cameras?.count ?? 0
    }

    var cameraMenuLabel: String {
        if let selectedCameraIndex {
            return "Camera: \(selectedCameraIndex)"
        } else {
            return "Camera: Free"
        }
    }

    var variantIndex: Int? {
        if let variants = gltf?.extensions?.khrMaterialsVariants?.variants,
           let selectedVariantIndex {
            return min(max(selectedVariantIndex, 0), variants.count - 1)
        } else {
            return nil
        }
    }

    var variantCount: Int {
        gltf?.extensions?.khrMaterialsVariants?.variants.count ?? 0
    }

    var variantMenuLabel: String {
        if variantCount == 0 {
            return "Variant: None"
        }
        if let variantIndex,
           let variant = gltf?.extensions?.khrMaterialsVariants?.variants[variantIndex],
           let name = variant.name, !name.isEmpty {
            return "Variant: \(name)"
        } else if let variantIndex {
            return "Variant: \(variantIndex)"
        } else {
            return "Variant: Default"
        }
    }

    func variantName(at index: Int) -> String {
        if let variants = gltf?.extensions?.khrMaterialsVariants?.variants,
           variants.indices.contains(index),
           let name = variants[index].name,
           !name.isEmpty {
            return name
        }
        return "\(index)"
    }
}
