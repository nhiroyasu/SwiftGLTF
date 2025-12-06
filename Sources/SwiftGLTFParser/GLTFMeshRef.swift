import ModelIO

@objc public protocol GLTFMeshRef: MDLComponent {
    var index: Int { get }
}

public class GLTFMeshRefImpl: NSObject, GLTFMeshRef {
    public let index: Int

    public init(index: Int) {
        self.index = index
        super.init()
    }
}
