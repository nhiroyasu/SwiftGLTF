import Testing
import ModelIO
@testable import SwiftGLTFParser
@testable import SwiftGLTFCore

struct EmissiveCubeTests {
    @Test
    func testEmissiveFactor() async throws {
        let (_, asset) = try await loadGLTFAndAsset()
        let mesh = asset.object(atPath: GLTFAssetPath.primitiveMesh(0)).children[0] as! MDLMesh
        let submesh = mesh.submeshes?.firstObject as! MDLSubmesh
        let material = submesh.material!
        let emissiveFactor = material.property(with: .emission)!
        let emissiveStrength = try #require(material.propertyNamed(.emissiveStrength))

        #expect(emissiveFactor.float3Value == SIMD3<Float>(0, 0, 1))
        #expect(emissiveStrength.floatValue == 20)
    }

    // MARK: - Helper Methods

    private func loadGLTFAndAsset() async throws -> (GLTF, MDLAsset) {
        guard let gltfURL = Bundle.module.url(forResource: "emissive_cube", withExtension: "gltf") else {
            throw NSError(domain: "CubeGLTFTests", code: -1, userInfo: [NSLocalizedDescriptionKey: "emissive_cube.gltf not found"])
        }
        let data = try Data(contentsOf: gltfURL)
        let gltfContainer = try await loadGLTF(from: data, baseURL: gltfURL.deletingLastPathComponent())
        let asset = try await makeMDLAsset(from: gltfContainer)
        return (gltfContainer.gltf, asset)
    }
}
