import AppKit
import XCTest
@testable import AmigaView

/// Records whatever a view passes up the responder chain.
private final class ChainSpy: NSResponder {
    var passed: [NSEvent.EventType] = []
    override func keyDown(with event: NSEvent) { passed.append(event.type) }
    override func keyUp(with event: NSEvent) { passed.append(event.type) }
    override func flagsChanged(with event: NSEvent) { passed.append(event.type) }
}

final class VideoViewKeyTests: XCTestCase {
    private func key(_ type: NSEvent.EventType, flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                         context: nil, characters: "a", charactersIgnoringModifiers: "a",
                         isARepeat: false, keyCode: 0)!
    }

    /// A key passed up the chain ends at noResponder, which beeps (typing, and
    /// any shortcut pressed while the window is key).
    func testKeysStopAtTheVideoView() {
        let view = VideoView(frame: .zero)
        let spy = ChainSpy()
        view.nextResponder = spy
        XCTAssertTrue(view.acceptsFirstResponder)
        view.keyDown(with: key(.keyDown, flags: [.control, .option]))
        view.keyUp(with: key(.keyUp))
        XCTAssertEqual(spy.passed, [])
    }

    /// Deskflow keeps input on the Mac while a button is held, so the switch fires on release.
    func testClickSwitchesOnMouseUpNotMouseDown() {
        let view = VideoView(frame: .zero)
        var clicks = 0
        view.onClick = { _ in clicks += 1 }
        func mouse(_ type: NSEvent.EventType) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                               context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        view.mouseDown(with: mouse(.leftMouseDown))
        XCTAssertEqual(clicks, 0)
        view.mouseUp(with: mouse(.leftMouseUp))
        XCTAssertEqual(clicks, 1)
    }
}
