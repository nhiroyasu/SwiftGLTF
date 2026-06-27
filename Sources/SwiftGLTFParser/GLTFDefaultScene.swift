import Foundation
import ModelIO
import SwiftGLTFCore

@objc public protocol GLTFDefaultScene: MDLComponent {
    var index: Int { get }
}

public class GLTFDefaultSceneImpl: NSObject, GLTFDefaultScene {
    public let index: Int
    public init(index: Int) { self.index = index }
}

@objc public protocol GLTFSceneRootNodesProtocol: MDLComponent {}

public class GLTFSceneRootNodes: NSObject, GLTFSceneRootNodesProtocol {
    public let nodes: [NodeIndex]

    public init(nodes: [NodeIndex]) {
        self.nodes = nodes
    }
}
