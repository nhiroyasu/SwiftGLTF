import Testing
import Foundation
@testable import SwiftGLTFCore

final class DefaultDecodingTests {
    @Test
    func testTopLevelArraysOptionalNil() throws {
        let json = """
        { "asset": { "version": "2.0" } }
        """.data(using: .utf8)!
        let gltf = try JSONDecoder().decode(GLTF.self, from: json)
        #expect(gltf.buffers == nil)
        #expect(gltf.bufferViews == nil)
        #expect(gltf.accessors == nil)
        #expect(gltf.meshes == nil)
        #expect(gltf.scenes == nil)
        #expect(gltf.nodes == nil)
        #expect(gltf.materials == nil)
        #expect(gltf.images == nil)
        #expect(gltf.textures == nil)
        #expect(gltf.samplers == nil)
    }

    @Test
    func testMaterialDefaults() throws {
        let json = """
        {
          "asset": { "version": "2.0" },
          "materials": [ { } ]
        }
        """.data(using: .utf8)!
        let gltf = try JSONDecoder().decode(GLTF.self, from: json)
        let m = try #require(gltf.materials?.first)
        #expect(m.alphaMode == .opaque)
        #expect(m.alphaCutoff == 0.5)
        #expect(m.doubleSided == false)
        #expect(m.emissiveFactor == [0,0,0])
    }

    @Test
    func testPBRDefaults() throws {
        let json = """
        {
          "asset": { "version": "2.0" },
          "materials": [ { "pbrMetallicRoughness": {} } ]
        }
        """.data(using: .utf8)!
        let gltf = try JSONDecoder().decode(GLTF.self, from: json)
        let pbr = try #require(gltf.materials?.first?.pbrMetallicRoughness)
        #expect(pbr.baseColorFactor == [1,1,1,1])
        #expect(pbr.metallicFactor == 1.0)
        #expect(pbr.roughnessFactor == 1.0)
    }

    @Test
    func testTextureInfoDefaults() throws {
        let json = """
        {
          "asset": { "version": "2.0" },
          "textures": [ {"source": 0} ],
          "images": [ {"uri": "data:image/png;base64,AAAA"} ],
          "materials": [ {
            "pbrMetallicRoughness": {
              "baseColorTexture": { "index": 0 }
            },
            "normalTexture": { "index": 0 },
            "occlusionTexture": { "index": 0 }
          } ]
        }
        """.data(using: .utf8)!
        let gltf = try JSONDecoder().decode(GLTF.self, from: json)
        let m = try #require(gltf.materials?.first)
        #expect(m.pbrMetallicRoughness?.baseColorTexture?.texCoord == 0)
        #expect(m.normalTexture?.texCoord == 0)
        #expect(m.normalTexture?.scale == 1.0)
        #expect(m.occlusionTexture?.texCoord == 0)
        #expect(m.occlusionTexture?.strength == 1.0)
    }

    @Test
    func testPrimitiveModeDefaultTriangles() throws {
        let json = """
        {
          "asset": { "version": "2.0" },
          "meshes": [ { "primitives": [ { "attributes": {"POSITION": 0} } ] } ],
          "accessors": [ { "componentType": 5126, "count": 0, "type": "VEC3" } ]
        }
        """.data(using: .utf8)!
        let gltf = try JSONDecoder().decode(GLTF.self, from: json)
        #expect(gltf.meshes?.first?.primitives.first?.mode == .triangles)
    }
}
