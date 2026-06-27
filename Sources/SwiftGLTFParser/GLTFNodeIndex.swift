import Foundation
import ModelIO
import simd
import SwiftGLTFCore

@objc public protocol GLTFNodeIndexProtocol: MDLComponent {}

public class GLTFNodeIndex: NSObject, GLTFNodeIndexProtocol {
    public let index: NodeIndex
    public init(index: NodeIndex) { self.index = index }
}

@objc public protocol GLTFNodeMetadataProtocol: MDLComponent {}

public class GLTFNodeMetadata: NSObject, GLTFNodeMetadataProtocol {
    public let originalName: String?
    public let children: [NodeIndex]

    public init(originalName: String?, children: [NodeIndex]) {
        self.originalName = originalName
        self.children = children
    }
}
