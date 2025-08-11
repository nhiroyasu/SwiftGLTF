import XCTest
@testable import SwiftGLTFCore

final class ErrorTests: XCTestCase {
    func testParseMissingAttributeCapturesContext() {
        let err = SwiftGLTFError.makeParse(
            .missingAttribute(name: "POSITION"),
            context: .capture(stage: .parse, jsonPointer: "/meshes/0/primitives/0/attributes/POSITION")
        )
        guard case let .parse(code, ctx, underlying) = err else {
            XCTFail("not parse error"); return
        }
        XCTAssertNil(underlying)
        XCTAssertEqual(ctx.stage, .parse)
        XCTAssertEqual(ctx.jsonPointer, "/meshes/0/primitives/0/attributes/POSITION")
        if case let .missingAttribute(name) = code {
            XCTAssertEqual(name, "POSITION")
        } else {
            XCTFail("unexpected code")
        }
        let ns = err as NSError
        XCTAssertEqual(ns.domain, "com.swiftgltf.error")
        XCTAssertEqual(ns.userInfo["SwiftGLTF.Stage"] as? String, "parse")
        XCTAssertNotNil(ns.userInfo["SwiftGLTF.FileID"])
    }
}

