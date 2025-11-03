import ModelIO

public class GLTF_MDLSubmesh: MDLSubmesh {
    public let materialIndex: Int

    init(
        name: String,
        indexBuffer: any MDLMeshBuffer,
        indexCount: Int,
        indexType: MDLIndexBitDepth,
        geometryType: MDLGeometryType,
        material: MDLMaterial?,
        materialIndex: Int
    ) {
        self.materialIndex = materialIndex
        super.init(
            name: name,
            indexBuffer: indexBuffer,
            indexCount: indexCount,
            indexType: indexType,
            geometryType: geometryType,
            material: material
        )
    }


}
