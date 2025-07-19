import Testing
import ModelIO
@testable import SwiftGLTF
@testable import SwiftGLTFCore

struct MaterialCubeTests {
    @Test
    func testMetallicRoughnessFactor() throws {
        let (_, asset) = try loadGLTFAndAsset()
        let mesh = asset.object(at: 0).children.objects[0] as! MDLMesh
        let submesh = mesh.submeshes?.firstObject as! MDLSubmesh
        let material = submesh.material!
        let metallicFactor = material.property(with: .metallic)!
        let roughnessFactor = material.property(with: .roughness)!

        #expect(metallicFactor.floatValue == 0.9)
        #expect(roughnessFactor.floatValue == 0.1)
    }

    @Test
    func testBaseColorFactor() throws {
        let (_, asset) = try loadGLTFAndAsset()
        let mesh = asset.object(at: 0).children.objects[0] as! MDLMesh
        let submesh = mesh.submeshes?.firstObject as! MDLSubmesh
        let material = submesh.material!
        let baseColorFactor = material.property(with: .baseColor)!

        #expect(baseColorFactor.float4Value == SIMD4<Float>(1.0, 0.0, 0.0, 1.0))
    }

    // MARK: - Helper Methods

    private func loadGLTFAndAsset() throws -> (GLTF, MDLAsset) {
        guard let gltfURL = Bundle.module.url(forResource: "material_cube", withExtension: "gltf") else {
            throw NSError(domain: "CubeGLTFTests", code: -1, userInfo: [NSLocalizedDescriptionKey: "material_cube.gltf not found"])
        }
        let data = try Data(contentsOf: gltfURL)
        let gltfContainer = try loadGLTF(from: data, baseURL: gltfURL.deletingLastPathComponent())
        let asset = try makeMDLAsset(from: gltfContainer)
        return (gltfContainer.gltf, asset)
    }
}
