import Testing
import Foundation
@testable import SwiftGLTFCore

struct TextureWebPExtensionDecodingTests {
    @Test
    func testTextureDecodesEXTTextureWebPWithFallbackSource() throws {
        let json = """
        {
          "asset": { "version": "2.0" },
          "images": [
            { "uri": "fallback.png" },
            { "uri": "priority.webp" }
          ],
          "textures": [
            {
              "source": 0,
              "extensions": {
                "EXT_texture_webp": {
                  "source": 1
                }
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let gltf = try JSONDecoder().decode(GLTF.self, from: json)
        let texture = try #require(gltf.textures?.first)
        #expect(texture.source?.value == 0)
        #expect(texture.extensions?.extTextureWebP?.source.value == 1)
    }

    @Test
    func testTextureDecodesEXTTextureWebPOnlySource() throws {
        let json = """
        {
          "asset": { "version": "2.0" },
          "images": [
            { "uri": "only.webp" }
          ],
          "textures": [
            {
              "extensions": {
                "EXT_texture_webp": {
                  "source": 0
                }
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let gltf = try JSONDecoder().decode(GLTF.self, from: json)
        let texture = try #require(gltf.textures?.first)
        #expect(texture.source == nil)
        #expect(texture.extensions?.extTextureWebP?.source.value == 0)
    }
}
