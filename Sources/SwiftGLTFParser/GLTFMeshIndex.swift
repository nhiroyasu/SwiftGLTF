import Foundation
import ModelIO
import simd

@objc public protocol GLTFMeshRef: MDLComponent {
    var index: Int { get }
    var mesh: MDLObject { get }
}

class GLTFMeshRefImpl: NSObject, GLTFMeshRef {
    let index: Int
    let mesh: MDLObject

    init(index: Int, mesh: MDLObject) {
        self.index = index
        self.mesh = mesh
    }
}
