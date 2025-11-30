import ModelIO

public class GLTFPrimitiveMesh: MDLObject {
    public var meshes: [MDLMesh] {
        var meshes: [MDLMesh] = []
        for child in self.children.objects {
            if let mesh = child as? MDLMesh {
                meshes.append(mesh)
            } else {
                assertionFailure("GLTFPrimitiveMesh child is not MDLMesh")
            }
        }
        return meshes
    }
}
