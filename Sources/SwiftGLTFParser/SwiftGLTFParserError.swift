import Foundation

public struct SwiftGLTFParserError: Error, Sendable {
    public let description: String

    public init(description: String) {
        self.description = description
    }
}

extension SwiftGLTFParserError: LocalizedError {
    public var errorDescription: String? {
        "[SwiftGLTFParser] \(description)"
    }
}

extension SwiftGLTFParserError: CustomNSError {
    public static var errorDomain: String { "com.swiftgltf.parser" }

    public var errorCode: Int { 0 }

    public var errorUserInfo: [String: Any] {
        [NSLocalizedDescriptionKey: self.errorDescription ?? "SwiftGLTFParserError"]
    }
}
