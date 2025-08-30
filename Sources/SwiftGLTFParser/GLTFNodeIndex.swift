import Foundation
import ModelIO
import simd

@objc public protocol GLTFNodeIndexProtocol: MDLComponent {}

public class GLTFNodeIndex: NSObject, GLTFNodeIndexProtocol {
    public let index: Int
    public init(index: Int) { self.index = index }
}
