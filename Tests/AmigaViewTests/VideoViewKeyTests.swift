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

    /// A key passed up the chain ends at noResponder, which beeps (typing, and the
    /// Control+Option+Command+F12 a click posts for Synergy).
    func testKeysStopAtTheVideoView() {
        let view = VideoView(frame: .zero)
        let spy = ChainSpy()
        view.nextResponder = spy
        XCTAssertTrue(view.acceptsFirstResponder)
        view.keyDown(with: key(.keyDown, flags: [.control, .option, .command]))
        view.keyUp(with: key(.keyUp))
        XCTAssertEqual(spy.passed, [])
    }
}
