import XCTest
@testable import AmigaViewCore

final class DeskflowLogTests: XCTestCase {
    func testParsesRealLines() {
        XCTAssertEqual(DeskflowLog.parse("[2026-10-26T23:59:44.572] INFO: switch from \"BMS-MAC001\" to \"replay\" at 0,539"), .switched(to: "replay"))
        XCTAssertEqual(DeskflowLog.parse("[2026-10-26T23:59:45.096] INFO: switch from \"replay\" to \"BMS-MAC001\" at 1796,1159"), .switched(to: "BMS-MAC001"))
        XCTAssertEqual(DeskflowLog.parse("[2026-10-26T16:58:02.515] DEBUG: locked by mouse buttonID: 0"), .lockedByMouse)
        XCTAssertNil(DeskflowLog.parse("[2026-10-26T16:58:02.515] DEBUG: something else"))
    }

    func testWatchdogNeedsThreeLocksInTwoSecondsOnAmiga() {
        var s = DeskflowState()
        s.apply(.lockedByMouse, at: 0); s.apply(.lockedByMouse, at: 0.5); s.apply(.lockedByMouse, at: 1)
        XCTAssertFalse(s.shouldRelease(trusted: true, now: 1), "Mac has the input")
        s.apply(.switched(to: "replay"), at: 1)
        for t in [10.0, 10.5, 11] { s.apply(.lockedByMouse, at: t) }
        XCTAssertFalse(s.shouldRelease(trusted: false, now: 11), "not trusted")
        XCTAssertTrue(s.shouldRelease(trusted: true, now: 11))
        for t in [11.2, 11.4, 11.6] { s.apply(.lockedByMouse, at: t) }
        XCTAssertFalse(s.shouldRelease(trusted: true, now: 11.6), "rate limit 2 s")
        for t in [13.1, 13.2, 13.3] { s.apply(.lockedByMouse, at: t) }
        XCTAssertTrue(s.shouldRelease(trusted: true, now: 13.3))
    }

    func testSlowLocksDoNotTrigger() {
        var s = DeskflowState()
        s.apply(.switched(to: "replay"), at: 0)
        for t in [1.0, 4, 7] { s.apply(.lockedByMouse, at: t) }
        XCTAssertFalse(s.shouldRelease(trusted: true, now: 7))
    }

    func testTailReadsOnlyNewLinesAndSurvivesTruncation() throws {
        let path = NSTemporaryDirectory() + UUID().uuidString + ".log"
        try "old line\n".write(toFile: path, atomically: true, encoding: .utf8)
        let tail = FileTail(path: path)
        XCTAssertEqual(tail.readNewLines(), [])
        let h = FileHandle(forWritingAtPath: path)!
        h.seekToEndOfFile(); h.write("new one\npart".data(using: .utf8)!)
        XCTAssertEqual(tail.readNewLines(), ["new one"])
        h.write("ial\n".data(using: .utf8)!); try h.close()
        XCTAssertEqual(tail.readNewLines(), ["partial"])
        try "fresh\n".write(toFile: path, atomically: true, encoding: .utf8)
        XCTAssertEqual(tail.readNewLines(), ["fresh"])
    }
}
