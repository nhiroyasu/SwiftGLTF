import Foundation

public struct SwiftGLTFError: Error, Sendable {
    public let description: String

    public init(description: String) {
        self.description = description
    }
}

extension SwiftGLTFError: LocalizedError {
    public var errorDescription: String? {
        "[SwiftGLTF] \(description)"
    }
}

extension SwiftGLTFError: CustomNSError {
    public static var errorDomain: String { "com.swiftgltf" }

    public var errorCode: Int { 0 }

    public var errorUserInfo: [String: Any] {
        [NSLocalizedDescriptionKey: self.errorDescription ?? "SwiftGLTFError"]
    }
}
