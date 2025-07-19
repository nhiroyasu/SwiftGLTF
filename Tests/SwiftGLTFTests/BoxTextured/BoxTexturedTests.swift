import Testing
import ModelIO
@testable import SwiftGLTF
@testable import SwiftGLTFCore

struct BoxTexturedTests {
    @Test
    func testEmbeddedTextureMatchesOriginalImage() throws {
        // Load glTF container with embedded image
        let (gltfContainer) = try loadGLTFContainer()
        // Expect exactly one texture
        #expect(gltfContainer.binaryTextures.count == 1)
        let actualTexture = gltfContainer.binaryTextures[0]

        // Load expected image from resource
        let pngURL = Bundle.module.url(forResource: "CesiumLogoFlat", withExtension: "png")!
        let expectedTexture = MDLURLTexture(url: pngURL, name: "CesiumLogoFlat")

        // Compare raw pixel data of textures
        let actualData = actualTexture.imageFromTexture()!.takeUnretainedValue().dataProvider!.data!
        let expectedData = expectedTexture.imageFromTexture()!.takeUnretainedValue().dataProvider!.data!
        #expect(actualData == expectedData)
    }

    // MARK: - Helper
    private func loadGLTFContainer() throws -> (GLTFContainer) {
        guard let gltfURL = Bundle.module.url(forResource: "EmbeddedBoxTextured", withExtension: "gltf") else {
            throw NSError(domain: "BoxTexturedTests", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "EmbeddedBoxTextured.gltf not found"])
        }
        let data = try Data(contentsOf: gltfURL)
        let container = try loadGLTF(from: data, baseURL: gltfURL.deletingLastPathComponent())
        return container
    }
}
