import Foundation
import Testing
import SwiftGLTFCore
@testable import SwiftGLTFParser

struct NodeHierarchyValidationTests {
    @Test
    func testInvalidChildNodeIndexThrows() throws {
        let gltf = try decodeGLTF(
            """
            {
              "asset": { "version": "2.0" },
              "nodes": [
                { "children": [1] }
              ],
              "scenes": [
                { "nodes": [0] }
              ]
            }
            """
        )

        #expect(throws: Error.self) {
            _ = try makeMDLAsset(from: makeBundle(gltf))
        }
    }

    @Test
    func testMultipleParentsThrows() throws {
        let gltf = try decodeGLTF(
            """
            {
              "asset": { "version": "2.0" },
              "nodes": [
                { "children": [2] },
                { "children": [2] },
                {}
              ],
              "scenes": [
                { "nodes": [0, 1] }
              ]
            }
            """
        )

        #expect(throws: Error.self) {
            _ = try makeMDLAsset(from: makeBundle(gltf))
        }
    }

    @Test
    func testCyclicNodeHierarchyThrows() throws {
        let gltf = try decodeGLTF(
            """
            {
              "asset": { "version": "2.0" },
              "nodes": [
                { "children": [1] },
                { "children": [0] }
              ]
            }
            """
        )

        #expect(throws: Error.self) {
            _ = try makeMDLAsset(from: makeBundle(gltf))
        }
    }

    private func decodeGLTF(_ json: String) throws -> GLTF {
        try JSONDecoder().decode(GLTF.self, from: Data(json.utf8))
    }

    private func makeBundle(_ gltf: GLTF) -> GLTFBundle {
        GLTFBundle(gltf: gltf, binaryBuffers: [], binaryTextures: [])
    }
}
