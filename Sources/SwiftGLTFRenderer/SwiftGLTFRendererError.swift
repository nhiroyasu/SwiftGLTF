import Foundation

public struct SwiftGLTFRendererError: Error, Sendable {
    public let description: String

    public init(description: String) {
        self.description = description
    }
}

extension SwiftGLTFRendererError: LocalizedError {
    public var errorDescription: String? {
        "[SwiftGLTFRenderer] \(description)"
    }
}

extension SwiftGLTFRendererError: CustomNSError {
    public static var errorDomain: String { "com.swiftgltf.renderer" }

    public var errorCode: Int { 0 }

    public var errorUserInfo: [String: Any] {
        [NSLocalizedDescriptionKey: self.errorDescription ?? "SwiftGLTFRendererError"]
    }
}
