import SwiftUI
import SwiftGLTFRenderer
import SwiftGLTF
import UniformTypeIdentifiers

struct ContentView: View {

    @StateObject private var viewModel = GLTFViewModel()

    var body: some View {
        VStack(spacing: 0) {
            if let renderer = viewModel.renderer {
                GLTFMetalView(renderer: renderer)
                    .edgesIgnoringSafeArea(.all)
            } else {
                Text("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            #if os(iOS)
            let openFilePlacement: ToolbarItemPlacement = .bottomBar
            let renderingPickerPlacement: ToolbarItemPlacement = .bottomBar
            #elseif os(macOS)
            let openFilePlacement: ToolbarItemPlacement = .primaryAction
            let renderingPickerPlacement: ToolbarItemPlacement = .navigation
            #endif
            ToolbarItem(placement: openFilePlacement) {
                Button {
                    viewModel.onTapOpenFile()
                } label: {
                    Text(viewModel.openBuffonTitle)
                }
            }
            ToolbarItem(placement: renderingPickerPlacement) {
                Picker("Mode", selection: $viewModel.mode) {
                    Text("PBR").tag(RenderingType.pbr)
                    Text("Wireframe").tag(RenderingType.wireframe)
                }
                .pickerStyle(SegmentedPickerStyle())
            }
        }
        .navigationTitle("GLTF Viewer")
        .fileImporter(
            isPresented: $viewModel.showFileImporter,
            allowedContentTypes: viewModel.allowedContentTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { await viewModel.load(url: url) }
            case .failure(let error):
                print(error)
            }
        }
        .onDrop(of: viewModel.allowedContentTypes, delegate: viewModel)
        .alert(
            viewModel.errorMessage,
            isPresented: $viewModel.showError,
            actions: {
                Button("OK", role: .cancel, action: {})
            }
        )
        .onChange(of: viewModel.mode, initial: false) { _, mode  in
            viewModel.updateRenderingMode(mode)
        }
        .task {
            await viewModel.loadDefaultAsset()
        }
    }
}
