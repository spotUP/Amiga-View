import Foundation
import ImageIO

public enum FrameDecoder {
    /// Decodes JPEG or PNG data to a CGImage; nil when the data is not an image.
    public static func decode(_ data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }
}
