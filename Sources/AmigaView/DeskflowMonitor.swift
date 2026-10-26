import AppKit
import AmigaViewCore

/// Glue: tails the Deskflow log, keeps DeskflowState, and posts the release. The clock, the
/// trust flag and the poster are injected so a test can drive it.
final class DeskflowMonitor {
    static let releasedStatus = "Released a stuck mouse button"
    static let amigaStatus = "Amiga has keyboard and mouse - leave off the left edge"
    static let releasedStatusDuration: TimeInterval = 3

    private let tail: FileTail
    private var state = DeskflowState()
    private let clock: () -> TimeInterval
    private let trusted: () -> Bool
    private let postRelease: () -> Void
    private var releasedAt: TimeInterval?

    init(path: String, clock: @escaping () -> TimeInterval, trusted: @escaping () -> Bool,
         postRelease: @escaping () -> Void = DeskflowMonitor.postMouseUp) {
        tail = FileTail(path: path)
        self.clock = clock; self.trusted = trusted; self.postRelease = postRelease
    }

    var amigaHasInput: Bool { state.amigaHasInput }

    /// A status to show instead of the normal one, or nil.
    var overrideStatus: String? {
        if let releasedAt, clock() - releasedAt < Self.releasedStatusDuration { return Self.releasedStatus }
        return state.amigaHasInput ? Self.amigaStatus : nil
    }

    func poll() {
        let now = clock()
        for line in tail.readNewLines() { if let e = DeskflowLog.parse(line) { state.apply(e, at: now) } }
        if state.shouldRelease(trusted: trusted(), now: now) {
            NSLog("Amiga-View: Deskflow refused to switch repeatedly; posting a left mouseUp")
            postRelease()
            releasedAt = now
        }
    }

    static func postMouseUp() {
        guard let p = CGEvent(source: nil)?.location else { return }
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }
}
