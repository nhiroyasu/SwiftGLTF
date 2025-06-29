import Testing
import ModelIO
@testable import SwiftGLTF
@testable import SwiftGLTFCore

struct PlainCubeTests {
    @Test
    func testMetallicRoughnessFactorIsDefaultValue() throws {
        let (_, asset) = try loadGLTFAndAsset()
        let mesh = asset.object(at: 0).children.objects[0] as! MDLMesh
        let submesh = mesh.submeshes?.firstObject as! MDLSubmesh
        let material = submesh.material!
        let metallicFactor = material.property(with: .metallic)!
        let roughnessFactor = material.property(with: .roughness)!

        #expect(metallicFactor.floatValue == 1.0)
        #expect(roughnessFactor.floatValue == 1.0)
    }

    @Test
    func testBaseColorFactorIsDefaultValue() throws {
        let (_, asset) = try loadGLTFAndAsset()
        let mesh = asset.object(at: 0).children.objects[0] as! MDLMesh
        let submesh = mesh.submeshes?.firstObject as! MDLSubmesh
        let material = submesh.material!
        let baseColorFactor = material.property(with: .baseColor)!

        #expect(baseColorFactor.float4Value == SIMD4<Float>(1.0, 1.0, 1.0, 1.0))
    }

    // MARK: - Helper Methods

    private func loadGLTFAndAsset() throws -> (GLTF, MDLAsset) {
        guard let gltfURL = Bundle.module.url(forResource: "plain_cube", withExtension: "gltf") else {
            throw NSError(domain: "CubeGLTFTests", code: -1, userInfo: [NSLocalizedDescriptionKey: "plain_cube.gltf not found"])
        }
        let data = try Data(contentsOf: gltfURL)
        let gltf = try loadGLTF(from: data)
        let asset = try makeMDLAsset(from: gltf, baseURL: gltfURL.deletingLastPathComponent())
        return (gltf, asset)
    }
}
