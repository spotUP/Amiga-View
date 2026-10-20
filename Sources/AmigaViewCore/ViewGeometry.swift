import CoreGraphics

/// Size and fitting maths for the 720x288 field shown at 2x vertical scale.
public enum ViewGeometry {
    public static let fieldSize = CGSize(width: 720, height: 288)
    public static let verticalScale: CGFloat = 2
    /// Displayed size at 1:1 horizontally (720x576, roughly 4:3 on a PAL screen).
    public static let actualSize = CGSize(width: fieldSize.width, height: fieldSize.height * verticalScale)
    public static var aspect: CGFloat { actualSize.width / actualSize.height }

    /// Displayed size for a multiple of the actual size.
    public static func size(scale: CGFloat) -> CGSize {
        CGSize(width: actualSize.width * scale, height: actualSize.height * scale)
    }

    /// Largest rectangle with the display aspect, centred in `bounds`.
    public static func fit(in bounds: CGSize) -> CGRect {
        guard bounds.width > 0, bounds.height > 0 else { return .zero }
        var w = bounds.width
        var h = w / aspect
        if h > bounds.height { h = bounds.height; w = h * aspect }
        return CGRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2, width: w, height: h)
    }
}
