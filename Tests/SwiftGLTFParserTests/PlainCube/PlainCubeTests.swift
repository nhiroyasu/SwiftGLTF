import Testing
import ModelIO
@testable import SwiftGLTFParser
@testable import SwiftGLTFCore

struct PlainCubeTests {
    @Test
    func testMetallicRoughnessFactorIsDefaultValue() async throws {
        let (_, asset) = try await loadGLTFAndAsset()
        let mesh = asset.object(atPath: GLTFAssetPath.primitiveMesh(0)).children[0] as! MDLMesh
        let submesh = mesh.submeshes?.firstObject as! MDLSubmesh
        let material = submesh.material!
        let metallicFactor = material.property(with: .metallic)!
        let roughnessFactor = material.property(with: .roughness)!

        #expect(metallicFactor.floatValue == 1.0)
        #expect(roughnessFactor.floatValue == 1.0)
    }

    @Test
    func testBaseColorFactorIsDefaultValue() async throws {
        let (_, asset) = try await loadGLTFAndAsset()
        let mesh = asset.object(atPath: GLTFAssetPath.primitiveMesh(0)).children[0] as! MDLMesh
        let submesh = mesh.submeshes?.firstObject as! MDLSubmesh
        let material = submesh.material!
        let baseColorFactor = material.property(with: .baseColor)!

        #expect(baseColorFactor.float4Value == SIMD4<Float>(1.0, 1.0, 1.0, 1.0))
    }

    // MARK: - Helper Methods

    private func loadGLTFAndAsset() async throws -> (GLTF, MDLAsset) {
        guard let gltfURL = Bundle.module.url(forResource: "plain_cube", withExtension: "gltf") else {
            throw NSError(domain: "CubeGLTFTests", code: -1, userInfo: [NSLocalizedDescriptionKey: "plain_cube.gltf not found"])
        }
        let data = try Data(contentsOf: gltfURL)
        let gltfContainer = try loadGLTF(from: data, baseURL: gltfURL.deletingLastPathComponent())
        let asset = try makeMDLAsset(from: gltfContainer)
        return (gltfContainer.gltf, asset)
    }
}
