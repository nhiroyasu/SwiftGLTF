import OSLog

enum Log {
    static let common = Logger(
        subsystem: "com.nhiroyasu.SwiftGLTFRenderer",
        category: "render"
    )
}
