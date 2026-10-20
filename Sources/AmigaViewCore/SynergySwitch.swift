import CoreGraphics
import Foundation

/// The global hotkey Deskflow binds to switchToScreen(replay): Control+Option+Command+F12.
public enum SynergySwitch {
    public static let keyCode: CGKeyCode = 0x6F // kVK_F12
    public static let flags: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]
    public static let debounce: TimeInterval = 0.5
    public static let defaultsKey = "switchSynergyOnClick"
    public static let untrustedStatus = "Grant Accessibility to switch Synergy on click"

    /// On by default; only an explicit false in the store turns it off.
    public static func isEnabled(in store: UserDefaults = .standard) -> Bool {
        store.object(forKey: defaultsKey) == nil ? true : store.bool(forKey: defaultsKey)
    }

    public static func setEnabled(_ on: Bool, in store: UserDefaults = .standard) {
        store.set(on, forKey: defaultsKey)
    }

    /// Whether a click at `now` should post the hotkey. `lastSent` is the time of the previous post.
    public static func shouldSend(enabled: Bool, trusted: Bool, lastSent: TimeInterval?, now: TimeInterval) -> Bool {
        guard enabled, trusted else { return false }
        guard let lastSent else { return true }
        return now - lastSent >= debounce
    }
}
