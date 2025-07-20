import MetalKit

extension MTLDevice {
    func makePackageLibrary() throws -> MTLLibrary {
        do {
            return try makeDefaultLibrary(bundle: Bundle.module)
        } catch {
            print("⚠️ Using custom metallib due to error: \(error)")
            // Fallback to custom metallib if default library creation fails
            print("🔄 Attempting to load custom metallib...")

            /*
             When running the `swift test` command in Swift Package Manager, there was an issue where the library could not be loaded in `Bundle.module`.
             As a workaround, we built .metallib ourselves and loaded it to avoid the issue.
             .metallib can be created with the `make` command.
             */
            let name: String = {
                #if os(macOS)
                return "SwiftGLTFRenderer.macosx"
                #elseif targetEnvironment(simulator)
                return "SwiftGLTFRenderer.iphonesimulator"
                #elseif os(iOS)
                return "SwiftGLTFRenderer.iphoneos"
                #elseif os(visionOS)
                return "SwiftGLTFRenderer.xros"
                #else
                fatalError("Unsupported platform")
                #endif
            }()

            let url = Bundle.module.url(forResource: name, withExtension: "metallib")!
            let library = try makeLibrary(URL: url)
            print("✅ Successfully loaded custom metallib from \(url.path)")
            return library
        }
    }
}
