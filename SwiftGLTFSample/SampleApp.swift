import SwiftUI

#if os(iOS)
@main
struct SwiftGLTFSampleApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
#elseif os(macOS)
@main
struct SwiftGLTFSampleApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
#endif
