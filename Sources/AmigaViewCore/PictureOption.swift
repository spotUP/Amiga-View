import Foundation

/// The View menu's picture toggles, each stored in UserDefaults and off by default.
public enum PictureOption: String, CaseIterable {
    case cropOverscan, integerScaling, scanlines

    public var defaultsKey: String { "picture." + rawValue }

    public func isEnabled(in store: UserDefaults = .standard) -> Bool { store.bool(forKey: defaultsKey) }

    public func setEnabled(_ on: Bool, in store: UserDefaults = .standard) { store.set(on, forKey: defaultsKey) }
}
