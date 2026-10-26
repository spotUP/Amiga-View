import AppKit
import AmigaViewCore

/// Keeps the window off the right edge of the desktop, where Deskflow returns the pointer from the
/// Amiga. A window over that edge takes the returning pointer, and a click there switches straight
/// back, so the Mac cannot be reached again.
final class EdgeGuard: NSObject, NSWindowDelegate {
    /// Union of the display frames. Injected so tests can supply a fixed desktop.
    var desktop: () -> CGRect = {
        NSScreen.screens.map(\.frame).reduce(CGRect.null) { $0.union($1) }
    }

    func apply(to window: NSWindow) {
        let clear = SynergySwitch.clearOfEdge(window.frame, desktop: desktop())
        if clear != window.frame { window.setFrame(clear, display: true) }
    }

    func windowDidMove(_ notification: Notification) {
        if let window = notification.object as? NSWindow { apply(to: window) }
    }

    func windowDidResize(_ notification: Notification) {
        if let window = notification.object as? NSWindow { apply(to: window) }
    }
}
