import CoreGraphics
import Foundation

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

    /// The whole field in field pixels.
    public static let fullField = CGRect(origin: .zero, size: fieldSize)
    /// Where the Amiga draws, measured from grabber snapshots (720x576, a field doubled): the
    /// grabber leaves black margins on the right (12 px) and below (one field line); the grey
    /// border colour the Amiga draws fills the rest.
    public static let defaultCrop = CGRect(x: 0, y: 0, width: 708, height: 287)
    public static let cropKeys = ["cropX", "cropY", "cropWidth", "cropHeight"]

    /// The crop in field pixels: `defaultCrop`, or the `cropX/cropY/cropWidth/cropHeight` defaults
    /// when all four are set and the rectangle lies inside the field.
    public static func cropRect(in store: UserDefaults = .standard) -> CGRect {
        guard cropKeys.allSatisfy({ store.object(forKey: $0) != nil }) else { return defaultCrop }
        let r = CGRect(x: store.double(forKey: "cropX"), y: store.double(forKey: "cropY"),
                       width: store.double(forKey: "cropWidth"), height: store.double(forKey: "cropHeight"))
        return r.width > 0 && r.height > 0 && fullField.contains(r) ? r : defaultCrop
    }

    /// Displayed size of `crop` (field pixels): full width, lines doubled.
    public static func displaySize(of crop: CGRect) -> CGSize {
        CGSize(width: crop.width, height: crop.height * verticalScale)
    }

    public static func aspect(of crop: CGRect) -> CGFloat {
        let s = displaySize(of: crop)
        return s.width / s.height
    }

    /// `CALayer.contentsRect` (unit square, origin at the bottom-left of the image) for a crop
    /// given in field pixels from the top-left.
    public static func contentsRect(for crop: CGRect) -> CGRect {
        CGRect(x: crop.minX / fieldSize.width, y: (fieldSize.height - crop.maxY) / fieldSize.height,
               width: crop.width / fieldSize.width, height: crop.height / fieldSize.height)
    }

    /// Largest rectangle with the aspect of `content`, centred in `bounds`.
    public static func fit(in bounds: CGSize, content: CGSize = actualSize) -> CGRect {
        guard bounds.width > 0, bounds.height > 0, content.width > 0, content.height > 0 else { return .zero }
        let aspect = content.width / content.height
        var w = bounds.width
        var h = w / aspect
        if h > bounds.height { h = bounds.height; w = h * aspect }
        return CGRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2, width: w, height: h)
    }

    /// Largest whole multiple of `content` that fits `bounds`, centred on whole points; the normal
    /// fit when even 1x does not fit.
    public static func integerFit(in bounds: CGSize, content: CGSize = actualSize) -> CGRect {
        guard bounds.width > 0, bounds.height > 0, content.width > 0, content.height > 0 else { return .zero }
        let n = floor(min(bounds.width / content.width, bounds.height / content.height))
        guard n >= 1 else { return fit(in: bounds, content: content) }
        let size = CGSize(width: content.width * n, height: content.height * n)
        return CGRect(x: ((bounds.width - size.width) / 2).rounded(.down),
                      y: ((bounds.height - size.height) / 2).rounded(.down),
                      width: size.width, height: size.height)
    }

    /// Share of black in the dark scanline rows.
    public static let scanlineDarkness: CGFloat = 0.35

    /// Black alpha (0...1) of each of the `2 * fieldLines` display rows, top to bottom: the first
    /// row of every field line is clear, the second dark.
    public static func scanlineAlphas(fieldLines: Int) -> [CGFloat] {
        (0..<max(fieldLines, 0) * Int(verticalScale)).map { $0 % 2 == 1 ? scanlineDarkness : 0 }
    }

    /// The picture as displayed: `crop` (field pixels) cut out of the field and every line doubled
    /// with the nearest filter, so 720x288 becomes 720x576. Used by snapshots and recordings.
    public static func displayImage(from field: CGImage, crop: CGRect = fullField) -> CGImage? {
        let r = crop.integral.intersection(CGRect(x: 0, y: 0, width: field.width, height: field.height))
        guard !r.isNull, r.width > 0, r.height > 0, let part = field.cropping(to: r),
              let ctx = CGContext(data: nil, width: part.width, height: part.height * Int(verticalScale), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        ctx.interpolationQuality = .none
        ctx.draw(part, in: CGRect(x: 0, y: 0, width: ctx.width, height: ctx.height))
        return ctx.makeImage()
    }
}
