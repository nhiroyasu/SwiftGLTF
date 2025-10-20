import Foundation
import ModelIO

@objc public protocol GLTFDefaultScene: MDLComponent {
    var index: Int { get }
}

public class GLTFDefaultSceneImpl: NSObject, GLTFDefaultScene {
    public let index: Int
    public init(index: Int) { self.index = index }
}
