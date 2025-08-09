import SwiftUI
import SwiftGLTFRenderer
import UniformTypeIdentifiers

struct ContentView: View {

    @StateObject private var viewModel = GLTFViewModel()

    var body: some View {
        VStack(spacing: 0) {
            if let url = viewModel.url {
                GLTFMetalView(url: url)
            }
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView("Loading...")
                    .progressViewStyle(CircularProgressViewStyle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.4))
            }
        }
        .toolbar {
            #if os(iOS)
            let openFilePlacement: ToolbarItemPlacement = .bottomBar
            #elseif os(macOS)
            let openFilePlacement: ToolbarItemPlacement = .primaryAction
            #endif
            ToolbarItem(placement: openFilePlacement) {
                Button {
                    viewModel.onTapOpenFile()
                } label: {
                    Text(viewModel.openBuffonTitle)
                }
            }
        }
        .navigationTitle("GLTF Viewer")
        .ignoresSafeArea(.container, edges: .all)
        .fileImporter(
            isPresented: $viewModel.showFileImporter,
            allowedContentTypes: viewModel.allowedContentTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                viewModel.load(url: url)
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
        .task {
            viewModel.loadDefaultAsset()
        }
    }
}
