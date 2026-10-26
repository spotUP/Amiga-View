import CoreGraphics
import Foundation

/// Moves Deskflow's keyboard and mouse to the Amiga ("replay", right of the Mac) on a click.
/// Deskflow does not react to a posted hotkey (synthetic keys never trigger its
/// switchToScreen keystroke, even with real modifier key-downs), but it does switch on
/// posted mouse moves that cross the screen edge, so the switch walks the pointer there.
public enum SynergySwitch {
    public static let edgeApproach: CGFloat = 20
    public static let edgeStep: CGFloat = 5
    public static let debounce: TimeInterval = 0.5
    public static let defaultsKey = "switchSynergyOnClick"
    /// Gap kept between the window and the right edge of the desktop. Deskflow brings the pointer
    /// back from the Amiga a few points inside that edge (x 1790-1798 of 1800 in its log); a window
    /// there catches it, and the next click sends input straight back to the Amiga.
    public static let edgeClearance: CGFloat = 16
    public static let untrustedStatus = "Grant Accessibility to switch Synergy on click"

    /// On by default; only an explicit false in the store turns it off.
    public static func isEnabled(in store: UserDefaults = .standard) -> Bool {
        store.object(forKey: defaultsKey) == nil ? true : store.bool(forKey: defaultsKey)
    }

    public static func setEnabled(_ on: Bool, in store: UserDefaults = .standard) {
        store.set(on, forKey: defaultsKey)
    }

    /// The pointer positions to post: from just inside the right edge of `desktop` (the union of
    /// the displays, in CoreGraphics coordinates) up to the edge, at the pointer's height. The
    /// last point is the crossing; a move posted after it reaches the Amiga as a jump and can
    /// carry the pointer back off its left edge.
    public static func edgePath(from pointer: CGPoint, desktop: CGRect) -> [CGPoint] {
        let y = min(max(pointer.y, desktop.minY), desktop.maxY - 1)
        return stride(from: desktop.maxX - edgeApproach, through: desktop.maxX, by: edgeStep)
            .map { CGPoint(x: $0, y: y) }
    }

    /// `frame` moved left as far as needed to end `edgeClearance` short of the right edge of
    /// `desktop`. Only x changes, so it holds in AppKit and CoreGraphics coordinates alike.
    public static func clearOfEdge(_ frame: CGRect, desktop: CGRect) -> CGRect {
        let limit = desktop.maxX - edgeClearance
        guard frame.maxX > limit else { return frame }
        return frame.offsetBy(dx: limit - frame.maxX, dy: 0)
    }

    /// Whether a click at `now` should switch. `lastSent` is the time of the previous switch.
    public static func shouldSend(enabled: Bool, trusted: Bool, lastSent: TimeInterval?, now: TimeInterval) -> Bool {
        guard enabled, trusted else { return false }
        guard let lastSent else { return true }
        return now - lastSent >= debounce
    }
}
