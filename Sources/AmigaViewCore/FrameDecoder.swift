import Foundation
import ImageIO

public enum FrameDecoder {
    /// Decodes JPEG or PNG data to a CGImage; nil when the data is not an image.
    /// The pixels are decoded here, on the caller's (network) queue: without
    /// kCGImageSourceShouldCacheImmediately the CGImage is lazy and the JPEG is decoded on the
    /// main thread when Core Animation first draws the layer, 50 times a second.
    public static func decode(_ data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }
}
