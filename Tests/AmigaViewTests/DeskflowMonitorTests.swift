import AppKit
import XCTest
@testable import AmigaView
@testable import AmigaViewCore

final class DeskflowMonitorTests: XCTestCase {
    /// Log lines in, border and release out, through the monitor and the view.
    func testLogDrivesBorderStatusAndRelease() throws {
        let path = NSTemporaryDirectory() + UUID().uuidString + ".log"
        try "".write(toFile: path, atomically: true, encoding: .utf8)
        var now: TimeInterval = 100
        var releases = 0
        let m = DeskflowMonitor(path: path, clock: { now }, trusted: { true }, postRelease: { releases += 1 })
        let view = VideoView(frame: .zero)
        func append(_ s: String) {
            let h = FileHandle(forWritingAtPath: path)!
            h.seekToEndOfFile(); h.write(s.data(using: .utf8)!); try? h.close()
        }
        func refresh() { m.poll(); view.amigaHasInput = m.amigaHasInput }

        refresh()
        XCTAssertEqual(view.layer?.borderWidth, 0)
        XCTAssertNil(m.overrideStatus)

        append("[2026-10-26T23:59:44.572] INFO: switch from \"BMS-MAC001\" to \"replay\" at 0,539\n")
        refresh()
        XCTAssertGreaterThan(view.layer?.borderWidth ?? 0, 0)
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
        XCTAssertEqual(view.layer?.borderWidth, 0)
        XCTAssertNil(m.overrideStatus)
    }

    /// The app starts while the Amiga already has the input: the first poll shows it.
    func testStartWhileAmigaHasInputShowsBorder() throws {
        let path = NSTemporaryDirectory() + UUID().uuidString + ".log"
        try "[t] INFO: switch from \"BMS-MAC001\" to \"replay\" at 0,539\n[t] DEBUG: locked by mouse buttonID: 0\n"
            .write(toFile: path, atomically: true, encoding: .utf8)
        var releases = 0
        let m = DeskflowMonitor(path: path, clock: { 100 }, trusted: { true }, postRelease: { releases += 1 })
        let view = VideoView(frame: .zero)
        m.poll(); view.amigaHasInput = m.amigaHasInput
        XCTAssertGreaterThan(view.layer?.borderWidth ?? 0, 0)
        XCTAssertEqual(m.overrideStatus, DeskflowMonitor.amigaStatus)
        XCTAssertEqual(releases, 0)
    }
}
