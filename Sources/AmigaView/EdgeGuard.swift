import AppKit
import AmigaViewCore

/// Keeps the window off the right edge of the desktop, where Deskflow returns the pointer from the
/// Amiga. A window over that edge takes the returning pointer, and a click there switches straight
/// back, so the Mac cannot be reached again.
///
/// Full screen is left alone: the system owns that frame, and moving it shifts the picture 16
/// points off the screen. Clicks near the edge are filtered by `SynergySwitch.isClickClearOfEdge`
/// instead. The guard stands down from the start of the enter transition to the end of the exit
/// transition, since the frame animates over the edge in between, and runs once again on exit.
final class EdgeGuard: NSObject, NSWindowDelegate {
    /// Union of the display frames. Injected so tests can supply a fixed desktop.
    var desktop: () -> CGRect = {
        NSScreen.screens.map(\.frame).reduce(CGRect.null) { $0.union($1) }
    }

    private var inFullScreen = false

    func apply(to window: NSWindow) {
        guard !inFullScreen, !window.styleMask.contains(.fullScreen) else { return }
        let clear = SynergySwitch.clearOfEdge(window.frame, desktop: desktop())
        if clear != window.frame { window.setFrame(clear, display: true) }
    }

    func windowDidMove(_ notification: Notification) {
        if let window = notification.object as? NSWindow { apply(to: window) }
    }

    func windowDidResize(_ notification: Notification) {
        if let window = notification.object as? NSWindow { apply(to: window) }
    }

    func windowWillEnterFullScreen(_ notification: Notification) {
        inFullScreen = true
    }

    func windowDidFailToEnterFullScreen(_ window: NSWindow) {
        inFullScreen = false
        apply(to: window)
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        inFullScreen = false
        if let window = notification.object as? NSWindow { apply(to: window) }
    }
}
