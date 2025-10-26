import Testing
import ModelIO
@testable import SwiftGLTFParser
@testable import SwiftGLTFCore

struct SimpleSkinTests {
    @Test
    func testSkeletonNode() async throws {
        let (_, asset) = try await loadGLTFAndAsset()
        let skin = asset.object(atPath: GLTFAssetPath.skins).children.objects.first as! GLTFSkin

        #expect(skin.joints == [1, 2])
        #expect(skin.jointObjects == [
            asset.object(atPath: GLTFAssetPath.nodes(atScene: 0) + "/Node_1"),
            asset.object(atPath: GLTFAssetPath.nodes(atScene: 0) + "/Node_1/Node_2")
        ])

        let expectedInverseBindMatrices = MDLMatrix4x4Array(elementCount: 2)
        expectedInverseBindMatrices.float4x4Array = [
            simd_float4x4(1),
            simd_float4x4(
                simd_float4(1, 0, 0, 0),
                simd_float4(0, 1, 0, 0),
                simd_float4(0, 0, 1, 0),
                simd_float4(0, -1, 0, 1)
            )
        ]
        #expect(skin.inverseBindMatrices.float4x4Array == expectedInverseBindMatrices.float4x4Array)
        #expect(skin.inverseBindMatrices.elementCount == expectedInverseBindMatrices.elementCount)
        #expect(skin.jointPaths == ["\(GLTFAssetPath.nodes(atScene: 0))/Node_1", "\(GLTFAssetPath.nodes(atScene: 0))/Node_1/Node_2"])
    }

    // MARK: - Helper Methods

    private func loadGLTFAndAsset() async throws -> (GLTF, MDLAsset) {
        guard let gltfURL = Bundle.module.url(forResource: "SimpleSkin", withExtension: "gltf") else {
            throw NSError(domain: "SimpleSkinTests", code: -1, userInfo: [NSLocalizedDescriptionKey: "SimpleSkin.gltf not found"])
        }
        let data = try Data(contentsOf: gltfURL)
        let gltfContainer = try loadGLTF(from: data, baseURL: gltfURL.deletingLastPathComponent())
        let asset = try makeMDLAsset(
            from: gltfContainer,
            options: GLTFDecodeOptions(convertToLeftHanded: false, autoScale: false)
        )
        return (gltfContainer.gltf, asset)
    }
}
