import ModelIO

public class GLTF_MDLSubmesh: MDLSubmesh {
    public let materialIndex: Int
    public let variantMappings: [GLTFVariantMapping]
    public let meshCenter: SIMD3<Float>

    init(
        name: String,
        indexBuffer: any MDLMeshBuffer,
        indexCount: Int,
        indexType: MDLIndexBitDepth,
        geometryType: MDLGeometryType,
        material: MDLMaterial?,
        materialIndex: Int,
        variantMappings: [GLTFVariantMapping],
        meshCenter: SIMD3<Float>
    ) {
        self.materialIndex = materialIndex
        self.variantMappings = variantMappings
        self.meshCenter = meshCenter
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
