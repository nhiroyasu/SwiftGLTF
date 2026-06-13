import Foundation
import ModelIO
import simd

@objc public protocol GLTFNodeIndexProtocol: MDLComponent {}

// TODO: Replace with NodeIndex
public class GLTFNodeIndex: NSObject, GLTFNodeIndexProtocol {
    public let index: Int
    public init(index: Int) { self.index = index }
}
