import AppKit
import XCTest
@testable import AmigaView
@testable import AmigaViewCore

final class DeskflowMonitorTests: XCTestCase {
    /// Log lines in, status and release out, through the monitor.
    func testLogDrivesStatusAndRelease() throws {
        let path = NSTemporaryDirectory() + UUID().uuidString + ".log"
        try "".write(toFile: path, atomically: true, encoding: .utf8)
        var now: TimeInterval = 100
        var releases = 0
        let m = DeskflowMonitor(path: path, clock: { now }, trusted: { true }, postRelease: { releases += 1 })
        func append(_ s: String) {
            let h = FileHandle(forWritingAtPath: path)!
            h.seekToEndOfFile(); h.write(s.data(using: .utf8)!); try? h.close()
        }
        func refresh() { m.poll() }

        refresh()
        XCTAssertFalse(m.amigaHasInput)
        XCTAssertNil(m.overrideStatus)

        append("[2026-10-26T23:59:44.572] INFO: switch from \"BMS-MAC001\" to \"replay\" at 0,539\n")
        refresh()
        XCTAssertTrue(m.amigaHasInput)
        XCTAssertEqual(m.overrideStatus, DeskflowMonitor.amigaStatus)
        XCTAssertEqual(releases, 0)

        for _ in 0..<3 { append("[2026-10-26T16:58:02.515] DEBUG: locked by mouse buttonID: 0\n") }
        refresh()
        XCTAssertEqual(releases, 1)
        XCTAssertEqual(m.overrideStatus, DeskflowMonitor.releasedStatus)
        now += 3.5
        XCTAssertEqual(m.overrideStatus, DeskflowMonitor.amigaStatus)

        append("[2026-10-26T23:59:45.096] INFO: switch from \"replay\" to \"BMS-MAC001\" at 1796,1159\n")
        refresh()
        XCTAssertFalse(m.amigaHasInput)
        XCTAssertNil(m.overrideStatus)
    }

    /// The app starts while the Amiga already has the input: the first poll shows it.
    func testStartWhileAmigaHasInputShowsStatus() throws {
        let path = NSTemporaryDirectory() + UUID().uuidString + ".log"
        try "[t] INFO: switch from \"BMS-MAC001\" to \"replay\" at 0,539\n[t] DEBUG: locked by mouse buttonID: 0\n"
            .write(toFile: path, atomically: true, encoding: .utf8)
        var releases = 0
        let m = DeskflowMonitor(path: path, clock: { 100 }, trusted: { true }, postRelease: { releases += 1 })
        m.poll()
        XCTAssertTrue(m.amigaHasInput)
        XCTAssertEqual(m.overrideStatus, DeskflowMonitor.amigaStatus)
        XCTAssertEqual(releases, 0)
    }
}
