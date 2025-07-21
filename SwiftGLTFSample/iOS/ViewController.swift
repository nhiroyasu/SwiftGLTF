import UIKit
import MetalKit
import SwiftGLTF
import SwiftGLTFRenderer

class ViewController: UIViewController {
    var device: MTLDevice!
    var commandQueue: MTLCommandQueue!
    var renderer: GLTFRenderer!

    override func viewDidLoad() {
        super.viewDidLoad()

        Task {
            device = MTLCreateSystemDefaultDevice()!
            commandQueue = device.makeCommandQueue()!

            do {
                let url = Bundle.main.url(forResource: "sphere-with-color", withExtension: "gltf")!
                let asset = try makeMDLAsset(from: url)
                try await setupMTLView(asset: asset)
            } catch {
                print("Error loading GLTF: \(error)")
            }

            // Add a button to open a GLTF file
            var config = UIButton.Configuration.filled()
            config.baseBackgroundColor = .systemBlue
            config.cornerStyle = .medium
            let openButton = UIButton(
                configuration: config,
                primaryAction: UIAction(
                    title: "Open .glb",
                    handler: { [weak self] _ in
                        self?.openGLTFFile()
                    }
                )
            )
            openButton.translatesAutoresizingMaskIntoConstraints = false
            self.view.addSubview(openButton)
            NSLayoutConstraint.activate([
                openButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                openButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
            ])
        }
    }

    func setupMTLView(asset: MDLAsset) async throws {
        renderer = try await GLTFRenderer()
        try await renderer.load(from: asset)

        let mtlView = MDLAssetPBRMTKView(frame: view.frame, renderer: renderer)
        mtlView.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(mtlView)
        NSLayoutConstraint.activate([
            mtlView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mtlView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mtlView.topAnchor.constraint(equalTo: view.topAnchor),
            mtlView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    func openGLTFFile() {
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.glb, .vrm])
        documentPicker.allowsMultipleSelection = false
        documentPicker.delegate = self
        present(documentPicker, animated: true, completion: nil)
    }

}

extension ViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        do {
            guard url.startAccessingSecurityScopedResource() else {
                throw NSError(domain: "SwiftGLTFSample", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to access the file."])
            }
            defer { url.stopAccessingSecurityScopedResource() }

            let asset = try makeMDLAsset(from: url)
            Task { try await setupMTLView(asset: asset) }
        } catch {
            let alert = UIAlertController(
                title: "Error",
                message: "Failed to load GLTF file: \(error.localizedDescription)",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            present(alert, animated: true, completion: nil)
        }
    }
}
