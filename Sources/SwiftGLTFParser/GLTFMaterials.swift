import ModelIO
import SwiftGLTFCore

public class GLTFMaterials: MDLObject {
    public let materials: [MDLMaterial]

    init(materials: [MDLMaterial]) {
        self.materials = materials
        super.init()
    }
}

@objc public protocol GLTFMaterialRef: MDLComponent {
    var materialIndex: Int { get }
}

class GLTFMaterialRefImpl: NSObject, GLTFMaterialRef {
    public let materialIndex: Int

    init(materialIndex: Int) {
        self.materialIndex = materialIndex
        super.init()
    }
}
