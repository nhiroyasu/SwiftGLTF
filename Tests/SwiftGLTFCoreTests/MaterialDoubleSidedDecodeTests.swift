import Testing
import Foundation
@testable import SwiftGLTFCore

final class MaterialDoubleSidedDecodeTests {
    @Test
    func testDoubleSidedOmittedDefaultsFalse() throws {
        let json = """
        {
          "asset": { "version": "2.0" },
          "materials": [ { "name": "mat0" } ]
        }
        """.data(using: .utf8)!
        let gltf = try JSONDecoder().decode(GLTF.self, from: json)
        #expect(gltf.materials?.count == 1)
        #expect(gltf.materials?.first?.doubleSided == false)
    }

    @Test
    func testDoubleSidedTrueDecodesTrue() throws {
        let json = """
        {
          "asset": { "version": "2.0" },
          "materials": [ { "name": "mat0", "doubleSided": true } ]
        }
        """.data(using: .utf8)!
        let gltf = try JSONDecoder().decode(GLTF.self, from: json)
        #expect(gltf.materials?.count == 1)
        #expect(gltf.materials?.first?.doubleSided == true)
    }
}

