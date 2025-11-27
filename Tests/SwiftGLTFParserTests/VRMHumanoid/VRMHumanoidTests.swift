import Testing
import ModelIO
@testable import SwiftGLTFParser
@testable import SwiftGLTFCore

struct VRMHumanoidTests {
    @Test
    func testHumanoidStoredOnAsset() async throws {
        let (_, asset) = try await loadGLTFAndAsset()
        let humanoidObject = asset.object(atPath: GLTFAssetPath.vrmHumanoid) as? GLTFVRMHumanoid
        let storedHumanoid = try #require(humanoidObject?.humanoid)
        #expect(storedHumanoid.humanBones.hips.node.value == 0)
        #expect(storedHumanoid.humanBones.head.node.value == 2)
    }

    private func loadGLTFAndAsset() async throws -> (GLTF, MDLAsset) {
        guard let gltfURL = Bundle.module.url(forResource: "humanoid", withExtension: "gltf") else {
            throw NSError(domain: "VRMHumanoidTests", code: -1, userInfo: [NSLocalizedDescriptionKey: "humanoid.gltf not found"])
        }
        let data = try Data(contentsOf: gltfURL)
        let bundle = try loadGLTF(from: data, baseURL: gltfURL.deletingLastPathComponent())
        let asset = try makeMDLAsset(
            from: bundle,
            options: GLTFDecodeOptions(convertToLeftHanded: false, autoScale: false)
        )
        return (bundle.gltf, asset)
    }
}
