import Foundation

/// The View menu's picture toggles, each stored in UserDefaults and off by default.
public enum PictureOption: String, CaseIterable {
    case cropOverscan, integerScaling

    public var defaultsKey: String { "picture." + rawValue }

    public func isEnabled(in store: UserDefaults = .standard) -> Bool { store.bool(forKey: defaultsKey) }

    public func setEnabled(_ on: Bool, in store: UserDefaults = .standard) { store.set(on, forKey: defaultsKey) }
}

/// The View menu's CRT Shader choice: one Mega Bezel preset, or none (the plain picture). Stored
/// in UserDefaults; none by default.
public enum CRTShader: String, CaseIterable {
    case smoothAdvancedGlass = "MBZ__0__SMOOTH-ADV-GLASS", smoothAdvanced = "MBZ__0__SMOOTH-ADV"
    case advanced = "MBZ__1__ADV", advancedGlass = "MBZ__2__ADV-GLASS", advancedNoReflection = "MBZ__2__ADV-NO-REFLECT"
    case standardGlass = "MBZ__3__STD-GLASS", standard = "MBZ__3__STD", standardNoReflection = "MBZ__4__STD-NO-REFLECT"
    case potato = "MBZ__5__POTATO"

    public static let defaultsKey = "picture.crtShader"

    public var title: String {
        switch self {
        case .smoothAdvancedGlass: return "Smooth Advanced Glass"
        case .smoothAdvanced: return "Smooth Advanced"
        case .advanced: return "Advanced"
        case .advancedGlass: return "Advanced Glass"
        case .advancedNoReflection: return "Advanced Without Reflection"
        case .standardGlass: return "Standard Glass"
        case .standard: return "Standard"
        case .standardNoReflection: return "Standard Without Reflection"
        case .potato: return "Potato"
        }
    }

    public static func selected(in store: UserDefaults = .standard) -> CRTShader? {
        store.string(forKey: defaultsKey).flatMap(CRTShader.init(rawValue:))
    }

    public static func select(_ shader: CRTShader?, in store: UserDefaults = .standard) {
        store.set(shader?.rawValue, forKey: defaultsKey)
    }

    /// The preset file below the shaders folder.
    public var presetPath: String { "bezel/Mega_Bezel/Presets/\(rawValue).slangp" }

    /// The shaders folder bundled by scripts/bundle.sh; a `swift build` binary has no bundle, so
    /// it falls back to build/shaders in the source tree (scripts/fetch-shaders.sh).
    public static func shadersURL(bundle: Bundle = .main) -> URL {
        bundle.url(forResource: "shaders", withExtension: nil)
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().appendingPathComponent("build/shaders")
    }
}
