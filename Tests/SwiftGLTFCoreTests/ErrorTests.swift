import XCTest
@testable import SwiftGLTFCore

final class ErrorTests: XCTestCase {
    func testParseErrorDescription() {
        let err = SwiftGLTFError.parser(description: "Missing attribute: POSITION")
        guard case let .parser(description) = err else {
            XCTFail("not parser error"); return
        }
        XCTAssertEqual(description, "Missing attribute: POSITION")
        XCTAssertEqual(err.errorDescription, "[SwiftGLTF][Parser] Missing attribute: POSITION")

        let ns = err as NSError
        XCTAssertEqual(ns.domain, "com.swiftgltf.error")
        XCTAssertEqual(ns.code, 0)
        XCTAssertEqual(ns.userInfo[NSLocalizedDescriptionKey] as? String, "[SwiftGLTF][Parser] Missing attribute: POSITION")
    }
}

