import Testing
import ModelIO
@testable import SwiftGLTF
@testable import SwiftGLTFCore

struct CubeWithTextureEmptySamplerTests {
    @Test
    func testSamplerFilterAndWrapSettings() throws {
        let (_, asset) = try loadGLTFAndAsset()
        let mesh = asset.object(at: 0).children.objects[0] as! MDLMesh
        let submesh = mesh.submeshes?.firstObject as! MDLSubmesh
        let material = submesh.material!

        let baseColorTextureProp = material.properties(with: .baseColor).first(where: { $0.type == .texture })!
        let sampler = baseColorTextureProp.textureSamplerValue!

        // compare filter modes
        #expect(sampler.hardwareFilter?.minFilter == .linear)
        #expect(sampler.hardwareFilter?.magFilter == .linear)

        // compare wrap modes
        #expect(sampler.hardwareFilter?.sWrapMode == .repeat)
        #expect(sampler.hardwareFilter?.tWrapMode == .repeat)
    }

    // MARK: - Helper Methods

    private func loadGLTFAndAsset() throws -> (GLTF, MDLAsset) {
        guard let gltfURL = Bundle.module.url(forResource: "bricks_cube_empty_sampler", withExtension: "gltf") else {
            throw NSError(domain: "CubeGLTFTests", code: -1, userInfo: [NSLocalizedDescriptionKey: "cube.gltf not found"])
        }
        let data = try Data(contentsOf: gltfURL)
        let gltfContainer = try loadGLTF(from: data, baseURL: gltfURL.deletingLastPathComponent())
        let asset = try makeMDLAsset(
            from: gltfContainer,
            options: .init(
                generateNormalVertexIfNeeded: false,
                generateTangentVertexIfNeeded: false
            )
        )
        return (gltfContainer.gltf, asset)
    }

    private func convertFilterMode(_ mode: GLTFFilterMode) -> MDLMaterialTextureFilterMode {
        switch mode {
        case .nearest, .nearestMipmapNearest, .nearestMipmapLinear:
            return .nearest
        case .linear, .linearMipmapNearest, .linearMipmapLinear:
            return .linear
        }
    }

    private func convertWrapMode(_ mode: GLTFWrapMode) -> MDLMaterialTextureWrapMode {
        switch mode {
        case .clampToEdge:
            return .clamp
        case .mirroredRepeat:
            return .mirror
        case .repeatWrap:
            return .repeat
        }
    }
}
