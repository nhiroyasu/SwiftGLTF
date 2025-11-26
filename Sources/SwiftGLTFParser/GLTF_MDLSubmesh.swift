import ModelIO

public class GLTF_MDLSubmesh: MDLSubmesh {
    public let materialIndex: Int
    public let variantMappings: [GLTFVariantMapping]

    init(
        name: String,
        indexBuffer: any MDLMeshBuffer,
        indexCount: Int,
        indexType: MDLIndexBitDepth,
        geometryType: MDLGeometryType,
        material: MDLMaterial?,
        materialIndex: Int,
        variantMappings: [GLTFVariantMapping]
    ) {
        self.materialIndex = materialIndex
        self.variantMappings = variantMappings
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
