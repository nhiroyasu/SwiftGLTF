import OSLog

enum Log {
    static let common = Logger(
        subsystem: "com.nhiroyasu.SwiftGLTFCore",
        category: "core"
    )
}
