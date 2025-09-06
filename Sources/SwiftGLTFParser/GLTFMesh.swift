import ModelIO

@objc public protocol GLTFMesh: MDLComponent {
    var primitives: [MDLMesh] { get }
}

public class GLTFMeshImpl: NSObject, GLTFMesh {
    public let primitives: [MDLMesh]

    init(primitives: [MDLMesh]) {
        self.primitives = primitives
    }
}
