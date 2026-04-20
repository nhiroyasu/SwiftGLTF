import Testing
import ModelIO
@testable import SwiftGLTFParser
@testable import SwiftGLTFCore

struct BoxTexturedTests {
    @Test
    func testEmbeddedTextureMatchesOriginalImage() throws {
        // Load glTF container with embedded image
        let gltfBundle = try loadGLTFBundle()
        // Expect exactly one texture
        #expect(gltfBundle.binaryTextures.count == 1)
        let actualTexture = gltfBundle.binaryTextures[0]

        // Load expected image from resource
        let pngURL = Bundle.module.url(forResource: "CesiumLogoFlat", withExtension: "png")!
        let expectedTexture = MDLURLTexture(url: pngURL, name: "CesiumLogoFlat")

        // Compare raw pixel data of textures
        let actualData = actualTexture.texelDataWithTopLeftOrigin()!
        let expectedData = expectedTexture.texelDataWithBottomLeftOrigin()!
        let assert = actualData == expectedData
        #expect(assert)
    }

    // MARK: - Helper
    private func loadGLTFBundle() throws -> (GLTFBundle) {
        guard let gltfURL = Bundle.module.url(forResource: "EmbeddedBoxTextured", withExtension: "gltf") else {
            throw NSError(domain: "BoxTexturedTests", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "EmbeddedBoxTextured.gltf not found"])
        }
        let data = try Data(contentsOf: gltfURL)
        let bundle = try loadGLTF(from: data, baseURL: gltfURL.deletingLastPathComponent())
        return bundle
    }
}
