import Testing
import ModelIO
@testable import SwiftGLTFParser
@testable import SwiftGLTFCore

struct SimpleSkinTests {
    @Test
    func testSkeletonNode() async throws {
        let (_, asset) = try await loadGLTFAndAsset()
        let skeleton = asset.object(at: 0).children[1] as! GLTFSkeleton

        #expect(skeleton.joins == [1, 2])
        #expect(skeleton.jointObjects == [asset.object(at: 1), asset.object(at: 1).children[0]])

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
        #expect(skeleton.inverseBindMatrices.float4x4Array == expectedInverseBindMatrices.float4x4Array)
        #expect(skeleton.inverseBindMatrices.elementCount == expectedInverseBindMatrices.elementCount)
        #expect(skeleton.jointPaths == ["/Node_1", "/Node_1/Node_2"])
    }

    // MARK: - Helper Methods

    private func loadGLTFAndAsset() async throws -> (GLTF, MDLAsset) {
        guard let gltfURL = Bundle.module.url(forResource: "SimpleSkin", withExtension: "gltf") else {
            throw NSError(domain: "SimpleSkinTests", code: -1, userInfo: [NSLocalizedDescriptionKey: "SimpleSkin.gltf not found"])
        }
        let data = try Data(contentsOf: gltfURL)
        let gltfContainer = try loadGLTF(from: data, baseURL: gltfURL.deletingLastPathComponent())
        let asset = try await makeMDLAsset(
            from: gltfContainer,
            options: GLTFDecodeOptions(convertToLeftHanded: false, autoScale: false)
        )
        return (gltfContainer.gltf, asset)
    }
}
