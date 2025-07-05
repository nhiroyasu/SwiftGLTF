import Testing
import ModelIO
@testable import SwiftGLTF
@testable import SwiftGLTFCore

struct EmissiveCubeTests {
    @Test
    func testEmissiveFactor() throws {
        let (_, asset) = try loadGLTFAndAsset()
        let mesh = asset.object(at: 0).children.objects[0] as! MDLMesh
        let submesh = mesh.submeshes?.firstObject as! MDLSubmesh
        let material = submesh.material!
        let emissiveFactor = material.property(with: .emission)!

        // Emissive strength extension multiplies the base factor (1.0) by 20.0 specified in the glTF
        #expect(emissiveFactor.float3Value == SIMD3<Float>(0, 0, 20))
    }

    // MARK: - Helper Methods

    private func loadGLTFAndAsset() throws -> (GLTF, MDLAsset) {
        guard let gltfURL = Bundle.module.url(forResource: "emissive_cube", withExtension: "gltf") else {
            throw NSError(domain: "CubeGLTFTests", code: -1, userInfo: [NSLocalizedDescriptionKey: "emissive_cube.gltf not found"])
        }
        let data = try Data(contentsOf: gltfURL)
        let gltf = try loadGLTF(from: data)
        let asset = try makeMDLAsset(from: gltf, baseURL: gltfURL.deletingLastPathComponent())
        return (gltf, asset)
    }
}
