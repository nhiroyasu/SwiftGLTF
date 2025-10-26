import SwiftUI
import UniformTypeIdentifiers
import SwiftGLTF

struct ContentView: View {

    @StateObject private var viewModel = GLTFViewModel()

    var body: some View {
        VStack(spacing: 0) {
            if let url = viewModel.url {
                GLTFSwiftUIView(
                    url: url,
                    sceneIndex: viewModel.sceneIndex,
                    environmentUrl: Bundle.main.url(forResource: "env_map", withExtension: "exr")!,
                    modelBinding: $viewModel.gltf,
                    showDebugHUD: true
                )
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
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Scene: Default") {
                        viewModel.selectedSceneIndex = nil
                    }
                    ForEach(0..<viewModel.sceneCount, id: \.self) { index in
                        Button("Scene: \(index)") {
                            viewModel.selectedSceneIndex = index
                        }
                    }
                } label: {
                    Text(viewModel.sceneMenuLabel)
                }
            }

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
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .ignoresSafeArea(.all)
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
