import Foundation

public enum SwiftGLTFError: Error, Sendable {
    case core(description: String)
    case parser(description: String)
    case render(description: String)
    case swiftgltf(description: String)
}

extension SwiftGLTFError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .core(description):
            return "[SwiftGLTF][Core] \(description)"
        case let .parser(description):
            return "[SwiftGLTF][Parser] \(description)"
        case let .render(description):
            return "[SwiftGLTF][Render] \(description)"
        case let .swiftgltf(description):
            return "[SwiftGLTF] \(description)"
        }
    }
}

extension SwiftGLTFError: CustomNSError {
    public static var errorDomain: String { "com.swiftgltf.error" }

    public var errorCode: Int { 0 }

    public var errorUserInfo: [String : Any] {
        [NSLocalizedDescriptionKey: self.errorDescription ?? "SwiftGLTFError"]
    }
}
