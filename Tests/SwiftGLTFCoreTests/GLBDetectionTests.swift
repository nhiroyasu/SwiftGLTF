import Foundation
import Testing
@testable import SwiftGLTFCore

/// Tests for GLB format detection helper
struct GLBDetectionTests {
    @Test
    func testIsGLBTrue() {
        // "glTF" magic header bytes
        let header: [UInt8] = [0x67, 0x6C, 0x54, 0x46]
        let trailing = [UInt8](repeating: 0, count: 8)
        let data = Data(header + trailing)
        #expect(isGLB(data) == true)
    }

    @Test
    func testIsGLBFalseShortData() {
        let data = Data([0x67, 0x6C, 0x54]) // less than 4 bytes
        #expect(isGLB(data) == false)
    }

    @Test
    func testIsGLBFalseWrongMagic() {
        let data = Data([0x00, 0x11, 0x22, 0x33, 0, 0, 0, 0])
        #expect(isGLB(data) == false)
    }
}
