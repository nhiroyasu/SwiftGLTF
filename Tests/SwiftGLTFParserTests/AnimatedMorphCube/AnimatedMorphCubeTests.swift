import Testing
import ModelIO
@testable import SwiftGLTFParser
@testable import SwiftGLTFCore

struct AnimatedMorphCubeTests {
    @Test
    func testMorphTargetsParsedFromAnimatedMorphCube() async throws {
        let (_, asset) = try await loadGLTFAndAsset()

        let mesh = asset.object(atPath: GLTFAssetPath.meshes).children[0] as! MDLMesh

        // Verify the Morph component
        let compAny = mesh.componentConforming(to: GLTFMorphTargets.self)
        #expect(compAny != nil)
        let comp = compAny as! GLTFMorphTargets

        #expect(comp.targetCount > 0)
        #expect(comp.targetMeshes.count == comp.targetCount)
        #expect(comp.vertexCount == mesh.vertexCount)

        let target0 = comp.targetMeshes[0]
        #expect(target0.vertexCount == mesh.vertexCount)

        let desc = target0.vertexDescriptor 
        let posAttr = desc.attributes[0] as? MDLVertexAttribute
        let nrmAttr = desc.attributes[1] as? MDLVertexAttribute
        let tanAttr = desc.attributes[2] as? MDLVertexAttribute
        #expect(posAttr?.format == .float3)
        #expect(nrmAttr?.format == .float3)
        #expect(tanAttr?.format == .float3)
        let layout0 = desc.layouts[0] as? MDLVertexBufferLayout
        #expect(layout0?.stride == MemoryLayout<Float>.size * 9)

        let expectedDefault = Array(repeating: Float(0), count: comp.targetCount)
        #expect(comp.defaultWeights == expectedDefault)
    }

    // MARK: - Helper Methods

    private func loadGLTFAndAsset() async throws -> (GLTF, MDLAsset) {
        guard let gltfURL = Bundle.module.url(forResource: "AnimatedMorphCube", withExtension: "gltf") else {
            throw NSError(domain: "AnimatedMorphCubeTests", code: -1, userInfo: [NSLocalizedDescriptionKey: "AnimatedMorphCube.gltf not found"])
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
