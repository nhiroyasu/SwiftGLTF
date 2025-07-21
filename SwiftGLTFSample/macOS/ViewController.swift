import Cocoa
import MetalKit
import OSLog
import SwiftGLTF
import SwiftGLTFRenderer

class ViewController: NSViewController {
    var device: MTLDevice!
    var commandQueue: MTLCommandQueue!
    var draggableView: DraggableView!
    var renderer: GLTFRenderer!

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
        renderer = try await GLTFRenderer()
        try renderer.load(from: asset)

        draggableView = DraggableView(frame: view.bounds) { [weak self] url in
            guard let self else { return }
            await showGLTF(url: url)
        }
        draggableView.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(draggableView)
        NSLayoutConstraint.activate([
            draggableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            draggableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            draggableView.topAnchor.constraint(equalTo: view.topAnchor),
            draggableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        let mtlView = MDLAssetPBRMTKView(frame: view.frame, renderer: renderer)
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

        let segmentedControl = NSSegmentedControl(labels: ["PBR", "Wireframe"], trackingMode: .selectOne, target: self, action: #selector(renderingModeChanged(_:)))
        segmentedControl.selectedSegment = 0
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(segmentedControl)
        NSLayoutConstraint.activate([
            segmentedControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            segmentedControl.bottomAnchor.constraint(equalTo: openButton.topAnchor, constant: -12)
        ])
    }

    @objc func openGLTFFile() {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.gltf, .glb, .vrm]
        openPanel.begin { [weak self] result in
            guard let self, result == .OK, let url = openPanel.url else { return }
            Task { [weak self] in
                await self?.showGLTF(url: url)
            }
        }
    }

    func showGLTF(url: URL) async {
        do {
            let asset = try makeMDLAsset(from: url, options: options)
            try renderer.load(from: asset)
        } catch {
            os_log("Error loading GLTF file: %@", type: .error, error.localizedDescription)
            NSAlert(error: error).runModal()
        }
    }

    @objc func renderingModeChanged(_ sender: NSSegmentedControl) {
        do {
            switch sender.selectedSegment {
            case 0:
                try renderer.reload(with: .pbr)
            case 1:
                try renderer.reload(with: .wireframe)
            default:
                break
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
