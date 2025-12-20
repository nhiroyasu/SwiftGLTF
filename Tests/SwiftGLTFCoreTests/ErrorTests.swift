import XCTest
@testable import SwiftGLTFCore

final class ErrorTests: XCTestCase {
    func testCoreErrorDescription() {
        let err = SwiftGLTFCoreError(description: "Missing attribute: POSITION")
        XCTAssertEqual(err.description, "Missing attribute: POSITION")
        XCTAssertEqual(err.errorDescription, "[SwiftGLTFCore] Missing attribute: POSITION")

        let ns = err as NSError
        XCTAssertEqual(ns.domain, "com.swiftgltf.core")
        XCTAssertEqual(ns.code, 0)
        XCTAssertEqual(ns.userInfo[NSLocalizedDescriptionKey] as? String, "[SwiftGLTFCore] Missing attribute: POSITION")
    }
}
