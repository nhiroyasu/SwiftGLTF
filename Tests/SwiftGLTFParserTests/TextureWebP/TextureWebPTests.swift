import Testing
import ModelIO
import Foundation
@testable import SwiftGLTFParser
@testable import SwiftGLTFCore

struct TextureWebPTests {
    private let fallbackPNGDataURI = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABAQMAAAAl21bKAAAABlBMVEUAAAD///+l2Z/dAAAACklEQVQI12NgAAAAAgAB4iG8MwAAAABJRU5ErkJggg=="

    @Test
    func testEXTTextureWebPPrioritizesWebPSource() throws {
        let sampler = try loadSampler(gltfName: "texture_webp_priority")
        let actualTexture = try #require(sampler.texture)

        let webPURL = try #require(Bundle.module.url(forResource: "TextureWebP_Priority", withExtension: "webp"))
        let expectedTexture = MDLURLTexture(url: webPURL, name: "ExpectedPriorityWebP")

        #expect(actualTexture.texelDataWithTopLeftOrigin() == expectedTexture.texelDataWithBottomLeftOrigin())
    }

    @Test
    func testEXTTextureWebPFallsBackToSourceWhenWebPIsUnavailable() throws {
        let sampler = try loadSampler(gltfName: "texture_webp_fallback_to_source")
        let actualTexture = try #require(sampler.texture)

        let fallbackData = try dataFromDataURI(fallbackPNGDataURI)
        let expectedTexture = try makeMDLTexture(from: fallbackData, name: "ExpectedFallbackPNG")

        #expect(actualTexture.texelDataWithTopLeftOrigin() == expectedTexture.texelDataWithTopLeftOrigin())
    }

    @Test
    func testEXTTextureWebPWorksWithoutFallbackSource() throws {
        let sampler = try loadSampler(gltfName: "texture_webp_only")
        let actualTexture = try #require(sampler.texture)

        let webPURL = try #require(Bundle.module.url(forResource: "TextureWebP_Only", withExtension: "webp"))
        let expectedTexture = MDLURLTexture(url: webPURL, name: "ExpectedOnlyWebP")

        #expect(actualTexture.texelDataWithTopLeftOrigin() == expectedTexture.texelDataWithBottomLeftOrigin())
    }

    private func loadSampler(gltfName: String) throws -> MDLTextureSampler {
        let gltfURL = try #require(Bundle.module.url(forResource: gltfName, withExtension: "gltf"))
        let data = try Data(contentsOf: gltfURL)
        let bundle = try loadGLTF(from: data, baseURL: gltfURL.deletingLastPathComponent())
        let binaryLoader = GLTFBinaryLoader(gltfBundle: bundle)
        let sampler = loadTextureSampler(textureIndex: 0, from: bundle.gltf, binaryLoader: binaryLoader)
        return try #require(sampler)
    }
}
