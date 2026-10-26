import AppKit
import XCTest
@testable import AmigaView

final class EdgeGuardTests: XCTestCase {
    /// Dragging the window over the right edge moves it back: the window delegate runs the clamp.
    func testWindowDraggedOverTheRightEdgeMovesBack() {
        let guardian = EdgeGuard()
        var asked = 0
        guardian.desktop = { asked += 1; return CGRect(x: 0, y: 0, width: 1800, height: 1169) }
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 720, height: 576),
                              styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.delegate = guardian
        window.setFrameOrigin(NSPoint(x: 1500, y: 100))
        XCTAssertGreaterThan(asked, 0)
        XCTAssertEqual(window.frame.maxX, 1800 - 16)
    }
}
