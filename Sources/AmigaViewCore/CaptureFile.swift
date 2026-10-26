import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// File names, PNG encoding and the clock text for snapshots and recordings.
public enum CaptureFile {
    /// "Amiga-View 2026-10-27 at 14.03.09.png", like macOS screenshots.
    public static func name(date: Date, ext: String, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Amiga-View \(f.string(from: date)).\(ext)"
    }

    /// The file's URL in `directory`; a name already taken gets " 2", " 3", ... before the extension.
    public static func url(in directory: URL, date: Date, ext: String, timeZone: TimeZone = .current,
                           exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
        let stem = String(name(date: date, ext: ext, timeZone: timeZone).dropLast(ext.count + 1))
        var url = directory.appendingPathComponent("\(stem).\(ext)"), n = 1
        while exists(url) {
            n += 1
            url = directory.appendingPathComponent("\(stem) \(n).\(ext)")
        }
        return url
    }

    public static func png(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    /// "mm:ss" (minutes keep counting past 59).
    public static func clock(_ seconds: TimeInterval) -> String {
        let s = max(Int(seconds), 0)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}
