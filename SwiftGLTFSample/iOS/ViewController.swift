import UIKit
import MetalKit
import SwiftGLTFCore
import SwiftGLTF
import SwiftGLTFRenderer

class ViewController: UIViewController {
    var device: MTLDevice!
    var commandQueue: MTLCommandQueue!
    var mtlView: MDLAssetPBRMTKView!

    override func viewDidLoad() {
        super.viewDidLoad()

        Task {
            device = MTLCreateSystemDefaultDevice()!
            commandQueue = device.makeCommandQueue()!

            do {
                let url = Bundle.main.url(forResource: "sphere-with-color", withExtension: "gltf")!
                let data = try Data(contentsOf: url)
                let gltf = try loadGLTF(from: data)
                let asset = try makeMDLAsset(from: gltf, baseURL: url.deletingLastPathComponent())
                try await  setupMTLView(asset: asset)
            } catch {
                print("Error loading GLTF: \(error)")
            }

            // Add a button to open a GLTF file
            // TODO: In the case of iOS, it is not possible to obtain read permission for bin and png files associated with glTF files, so the Open button will not be displayed until .glb files are supported.
            /*
            let openButton = UIButton(
                configuration: .bordered(),
                primaryAction: UIAction(
                    title: "Open GLTF File",
                    handler: { [weak self] _ in
                        self?.openGLTFFile()
                    }
                )
            )
            openButton.translatesAutoresizingMaskIntoConstraints = false
            self.view.addSubview(openButton)
            NSLayoutConstraint.activate([
                openButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                openButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20)
            ])
             */
        }
    }

    func setupMTLView(asset: MDLAsset) async throws {
        mtlView = try await MDLAssetPBRMTKView(
            frame: view.frame,
            device: device,
            commandQueue: commandQueue,
            asset: asset
        )
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
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.gltf, .glb])
        documentPicker.allowsMultipleSelection = false
        documentPicker.delegate = self
        present(documentPicker, animated: true, completion: nil)
    }

}

extension ViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        do {
            let data = try Data(contentsOf: url)
            let gltf = try loadGLTF(from: data, baseURL: url.deletingLastPathComponent())
            let asset = try makeMDLAsset(from: gltf)
            try mtlView.setAsset(asset)
        } catch {
            print("Error loading GLTF file: \(error)")
        }
    }
}
