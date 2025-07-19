import Foundation
import Testing
@testable import SwiftGLTFCore

/// Tests for Data URI helper functions in Loader
struct LoaderDataURITests {
    @Test
    func testDataFromDataURIBasic() throws {
        // Prepare a simple base64 string
        let original = "Hello, World!"
        let originalData = original.data(using: .utf8)!
        let b64 = originalData.base64EncodedString()
        let uri = "data:application/octet-stream;base64,\(b64)"
        let decoded = try dataFromDataURI(uri)
        #expect(decoded == originalData)
    }

    @Test
    func testMDLTextureFromDataURIMinimalPNG() throws {
        // 1x1 transparent PNG base64
        let b64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABAQMAAAAl21bKAAAABlBMVEUAAAD///+l2Z/dAAAACklEQVQI12NgAAAAAgAB4iG8MwAAAABJRU5ErkJggg=="
        let uri = "data:image/png;base64,\(b64)"
        let texture = try mdlTextureFromDataURI(uri, name: "TestPNG")
        // Expect dimensions 1x1 and 4 channels RGBA
        #expect(texture.dimensions.x == 1)
        #expect(texture.dimensions.y == 1)
        #expect(texture.channelCount == 4)
        #expect(texture.rowStride == 4)
    }
}
