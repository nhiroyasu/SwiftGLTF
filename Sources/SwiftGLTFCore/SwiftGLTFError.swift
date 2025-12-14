import Foundation

public struct SwiftGLTFCoreError: Error, Sendable {
    public let description: String

    public init(description: String) {
        self.description = description
    }
}

extension SwiftGLTFCoreError: LocalizedError {
    public var errorDescription: String? {
        "[SwiftGLTFCore] \(description)"
    }
}

extension SwiftGLTFCoreError: CustomNSError {
    public static var errorDomain: String { "com.swiftgltf.core" }

    public var errorCode: Int { 0 }

    public var errorUserInfo: [String: Any] {
        [NSLocalizedDescriptionKey: self.errorDescription ?? "SwiftGLTFCoreError"]
    }
}
