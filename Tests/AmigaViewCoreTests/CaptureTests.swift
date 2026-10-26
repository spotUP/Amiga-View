import AVFoundation
import ImageIO
import XCTest
@testable import AmigaViewCore

final class CaptureTests: XCTestCase {
    /// A 720x288 field whose pixel at (x, y) is red = y, green = x, blue = 7.
    static func field() -> CGImage {
        let ctx = CGContext(data: nil, width: 720, height: 288, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        for y in 0..<288 { for x in 0..<720 {
            ctx.setFillColor(red: CGFloat(y % 256) / 255, green: CGFloat(x % 256) / 255, blue: 7.0 / 255, alpha: 1)
            ctx.fill(CGRect(x: x, y: 287 - y, width: 1, height: 1))   // CGContext's origin is the bottom
        } }
        return ctx.makeImage()!
    }

    /// (red, green) of the pixel at (x, y), top-left origin.
    static func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (Int, Int) {
        let data = image.dataProvider!.data! as Data
        let o = y * image.bytesPerRow + x * 4   // BGRA
        return (Int(data[o + 2]), Int(data[o + 1]))
    }

    func testDisplayImageDoublesRowsAndAppliesCrop() {
        let full = ViewGeometry.displayImage(from: Self.field())!
        XCTAssertEqual(full.width, 720); XCTAssertEqual(full.height, 576)
        for y in [0, 1, 100, 101, 574, 575] {   // rows 2k and 2k+1 both show field line k
            let (r, g) = Self.pixel(full, 300, y)
            XCTAssertEqual(r, (y / 2) % 256, "row \(y)"); XCTAssertEqual(g, 300 % 256)
        }
        let cropped = ViewGeometry.displayImage(from: Self.field(), crop: CGRect(x: 4, y: 2, width: 700, height: 280))!
        XCTAssertEqual(cropped.width, 700); XCTAssertEqual(cropped.height, 560)
        XCTAssertEqual(Self.pixel(cropped, 0, 0).0, 2); XCTAssertEqual(Self.pixel(cropped, 0, 0).1, 4)
        XCTAssertEqual(Self.pixel(cropped, 0, 3).0, 3)
        let def = ViewGeometry.displayImage(from: Self.field(), crop: ViewGeometry.defaultCrop)!
        XCTAssertEqual(CGSize(width: def.width, height: def.height), ViewGeometry.displaySize(of: ViewGeometry.defaultCrop))
    }

    func testFileNames() {
        let utc = TimeZone(identifier: "UTC")!
        let date = Date(timeIntervalSince1970: 1_792_000_000)   // 2026-10-14 17:46:40 UTC
        XCTAssertEqual(CaptureFile.name(date: date, ext: "png", timeZone: utc), "Amiga-View 2026-10-14 at 17.46.40.png")
        let dir = URL(fileURLWithPath: "/x")
        XCTAssertEqual(CaptureFile.url(in: dir, date: date, ext: "mov", timeZone: utc, exists: { _ in false }).path, "/x/Amiga-View 2026-10-14 at 17.46.40.mov")
        XCTAssertEqual(CaptureFile.url(in: dir, date: date, ext: "mov", timeZone: utc, exists: { !$0.lastPathComponent.hasSuffix(" 3.mov") }).lastPathComponent,
                       "Amiga-View 2026-10-14 at 17.46.40 3.mov")
        XCTAssertEqual(CaptureFile.clock(12.9), "00:12"); XCTAssertEqual(CaptureFile.clock(754), "12:34")
        XCTAssertEqual(CGImage.pngSize(CaptureFile.png(Self.field())!), CGSize(width: 720, height: 288))
    }

    private func tempURL() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("capture-" + UUID().uuidString)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir.appendingPathComponent("t.mov")
    }

    private func recordVideoAndAudio(to url: URL) throws -> Recorder {
        let field = Self.field()
        let r = try Recorder(url: url, withAudio: true)
        let chunk = Data(count: 4800 * 4)   // 100 ms of silence
        for i in 0..<50 {
            r.push(frame: field, at: 100 + Double(i) * 0.02)
            if i % 5 == 0 { r.push(pcm: chunk) }
            if i % 10 == 9 { Thread.sleep(forTimeInterval: 0.05) }   // let the encoder keep up
        }
        r.finishAndWait()
        return r
    }

    private func recordWithStall(to url: URL) throws {
        let field = Self.field()
        let r = try Recorder(url: url, crop: ViewGeometry.defaultCrop, withAudio: false)
        for t in [10.0, 10.02, 10.04, 10.54, 10.56] { r.push(frame: field, at: t); Thread.sleep(forTimeInterval: 0.05) }
        r.push(pcm: Data(count: 4800))   // no audio input: ignored
        r.finishAndWait()
    }

    func testRecorderWritesVideoAndAudio() async throws {
        let url = tempURL()
        let r = try recordVideoAndAudio(to: url)
        XCTAssertEqual(r.droppedCount, 0)
        let asset = AVURLAsset(url: url)
        let video = try await asset.loadTracks(withMediaType: .video), audio = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(video.count, 1); XCTAssertEqual(audio.count, 1)
        let size = try await video[0].load(.naturalSize)
        XCTAssertEqual(size, CGSize(width: 720, height: 576))
        let seconds = try await asset.load(.duration).seconds
        XCTAssertEqual(seconds, 1.0, accuracy: 0.1)
    }

    /// Presentation times follow arrival, not a fixed rate: a stall of half a second shows in the duration;
    /// a cropped recording has the cropped size and no audio track.
    func testRecorderFollowsArrivalTimeAndCrop() async throws {
        let url = tempURL()
        try recordWithStall(to: url)
        let asset = AVURLAsset(url: url)
        let video = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(video.count, 1)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        let size = try await video[0].load(.naturalSize), seconds = try await asset.load(.duration).seconds
        XCTAssertEqual(audio.count, 0)
        XCTAssertEqual(size, CGSize(width: 708, height: 574))
        XCTAssertEqual(seconds, 0.56, accuracy: 0.1)
    }
}

extension CGImage {
    static func pngSize(_ data: Data) -> CGSize {
        let src = CGImageSourceCreateWithData(data as CFData, nil)!
        let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil)! as! [CFString: Any]
        return CGSize(width: p[kCGImagePropertyPixelWidth] as! Int, height: p[kCGImagePropertyPixelHeight] as! Int)
    }
}
