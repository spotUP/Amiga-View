import XCTest
@testable import AmigaViewCore

final class MultipartParserTests: XCTestCase {
    func part(_ body: String, boundary: String = "frame", extra: String = "", length: Bool = true) -> Data {
        var s = "--\(boundary)\r\nContent-Type: image/jpeg\r\n"
        if length { s += "Content-Length: \(body.utf8.count)\r\n" }
        s += extra + "\r\n" + body + "\r\n"
        return Data(s.utf8)
    }

    func testSinglePart() {
        var p = MultipartParser(boundary: "frame")
        XCTAssertEqual(p.feed(part("AAAA")).map { String(decoding: $0, as: UTF8.self) }, ["AAAA"])
    }

    func testBoundarySplitAcrossChunks() {
        var p = MultipartParser(boundary: "frame")
        let all = part("HELLO") + part("WORLD")
        var out: [String] = []
        for byte in all { out += p.feed(Data([byte])).map { String(decoding: $0, as: UTF8.self) } }
        // The last part is only complete once Content-Length bytes arrived.
        XCTAssertEqual(out, ["HELLO", "WORLD"])
    }

    func testMultiplePartsInOneChunk() {
        var p = MultipartParser(boundary: "--frame")
        let parts = p.feed(part("one") + part("two") + part("three"))
        XCTAssertEqual(parts.count, 3)
        XCTAssertEqual(String(decoding: parts[2], as: UTF8.self), "three")
    }

    func testNoContentLengthUsesNextBoundary() {
        var p = MultipartParser(boundary: "frame")
        let parts = p.feed(part("aa", length: false) + part("bb", length: false))
        XCTAssertEqual(parts.map { String(decoding: $0, as: UTF8.self) }, ["aa"])
        let more = p.feed(part("cc", length: false))
        XCTAssertEqual(more.map { String(decoding: $0, as: UTF8.self) }, ["bb"])
    }

    func testHeaderVariantsLowercaseAndBareLF() {
        var p = MultipartParser(boundary: "b")
        let d = Data("--b\ncontent-length: 3\n\nxyz\n".utf8)
        XCTAssertEqual(p.feed(d).map { String(decoding: $0, as: UTF8.self) }, ["xyz"])
    }

    func testBoundaryLearnedFromStream() {
        var p = MultipartParser()
        let parts = p.feed(part("q", boundary: "whatever"))
        XCTAssertEqual(parts.count, 1)
        XCTAssertEqual(p.boundary.map { String(decoding: $0, as: UTF8.self) }, "--whatever")
    }

    func testBoundaryFromContentType() {
        XCTAssertEqual(MultipartParser.boundary(fromContentType: "multipart/x-mixed-replace; boundary=\"FRAME\""), "FRAME")
        XCTAssertEqual(MultipartParser.boundary(fromContentType: "multipart/x-mixed-replace;boundary=--f"), "--f")
        XCTAssertNil(MultipartParser.boundary(fromContentType: "image/png"))
    }

    func testKeepsNewestFrameOnly() {
        var p = MultipartParser(boundary: "frame")
        let newest = p.feedNewest(part("old") + part("mid") + part("new"))
        XCTAssertEqual(newest.map { String(decoding: $0, as: UTF8.self) }, "new")
        XCTAssertNil(p.feedNewest(Data()))
    }

    func testBinaryBodyContainingBoundaryText() {
        var p = MultipartParser(boundary: "frame")
        let body = "xx--frame yy"
        XCTAssertEqual(p.feed(part(body)).map { String(decoding: $0, as: UTF8.self) }, [body])
    }
}
