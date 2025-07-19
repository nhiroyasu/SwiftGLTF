import Cocoa
import MetalKit
import OSLog
import SwiftGLTF
import SwiftGLTFRenderer

class ViewController: NSViewController {
    var device: MTLDevice!
    var commandQueue: MTLCommandQueue!
    var draggableView: DraggableView!
    var mtlView: MDLAssetPBRMTKView!

    let options: GLTFDecodeOptions = .default

    override func viewDidLoad() {
        super.viewDidLoad()

        Task {
            device = MTLCreateSystemDefaultDevice()!
            commandQueue = device.makeCommandQueue()!
            
            do {
                let url = Bundle.main.url(forResource: "sphere-with-color", withExtension: "gltf")!
                let asset = try makeMDLAsset(from: url, options: options)
                try await  setup(asset: asset)
            } catch {
                print("Error loading GLTF: \(error)")
            }
        }
    }

    func setup(asset: MDLAsset) async throws {
        draggableView = DraggableView(frame: view.bounds) { [weak self] url in
            guard let self else { return }
            showGLTF(url: url)
        }
        draggableView.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(draggableView)
        NSLayoutConstraint.activate([
            draggableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            draggableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            draggableView.topAnchor.constraint(equalTo: view.topAnchor),
            draggableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        mtlView = try await MDLAssetPBRMTKView(
            frame: view.frame,
            device: device,
            commandQueue: commandQueue,
            asset: asset
        )
        mtlView.translatesAutoresizingMaskIntoConstraints = false
        self.draggableView.addSubview(mtlView)
        NSLayoutConstraint.activate([
            mtlView.leadingAnchor.constraint(equalTo: draggableView.leadingAnchor),
            mtlView.trailingAnchor.constraint(equalTo: draggableView.trailingAnchor),
            mtlView.topAnchor.constraint(equalTo: draggableView.topAnchor),
            mtlView.bottomAnchor.constraint(equalTo: draggableView.bottomAnchor)
        ])

        // Add a button to open a GLTF file
        let openButton = NSButton(title: "Open .gltf or .glb", target: self, action: #selector(openGLTFFile))
        openButton.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(openButton)
        NSLayoutConstraint.activate([
            openButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            openButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20)
        ])
    }

    @objc func openGLTFFile() {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.gltf, .glb]
        openPanel.begin { [weak self] result in
            guard let self, result == .OK, let url = openPanel.url else { return }
            showGLTF(url: url)
        }
    }

    func showGLTF(url: URL) {
        do {
            let asset = try makeMDLAsset(from: url, options: options)
            try mtlView.setAsset(asset)
        } catch {
            os_log("Error loading GLTF file: %@", type: .error, error.localizedDescription)
            NSAlert(error: error).runModal()
        }
    }

}
