import AppKit
import AVFoundation
import ImageIO
import XCTest
@testable import AmigaView
@testable import AmigaViewCore

@MainActor
final class CaptureMenuTests: XCTestCase {
    private var app: AppDelegate!
    private var suite = ""
    private var dir: URL!

    override func setUp() {
        _ = NSApplication.shared
        suite = "capture-tests-" + UUID().uuidString
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        app = AppDelegate()
        app.defaults = UserDefaults(suiteName: suite)!
        app.frameAutosaveName = nil
        app.snapshotDirectory = dir; app.recordingDirectory = dir
        app.buildWindow()
        app.window.setFrameOrigin(NSPoint(x: 100, y: 100))
        app.buildMenu()
    }

    override func tearDown() {
        UserDefaults(suiteName: suite)!.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: dir)
    }

    private func item(_ title: String) throws -> NSMenuItem {
        try XCTUnwrap(NSApp.mainMenu?.items.compactMap(\.submenu).flatMap(\.items).first { $0.title == title }, title)
    }

    private func invoke(_ title: String) throws {
        let i = try item(title)
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(i.action), to: i.target, from: i))
    }

    private func files(_ ext: String) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == ext }
    }

    private func field() -> CGImage {
        let ctx = CGContext(data: nil, width: 720, height: 288, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: 720, height: 288))
        return ctx.makeImage()!
    }

    func testFileMenuSitsBetweenAppAndView() throws {
        let top = NSApp.mainMenu!.items.compactMap { $0.submenu?.title }
        XCTAssertEqual(Array(top.dropFirst()).prefix(2), ["File", "View"])
        XCTAssertEqual(try item("Save Snapshot").keyEquivalent, "s")
        XCTAssertEqual(try item("Start Recording").keyEquivalent, "r")
    }

    /// The tab bar showed one useless tab, "Amiga-View": the app has one window, so tabbing is off.
    func testWindowHasNoTabBar() {
        XCTAssertFalse(NSWindow.allowsAutomaticWindowTabbing)
        XCTAssertEqual(app.window.tabbingMode, .disallowed)
    }

    func testSnapshotWritesThePicture() throws {
        try invoke("Save Snapshot")   // no frame yet
        XCTAssertTrue(files("png").isEmpty)
        app.video.image = field()
        try invoke("Save Snapshot")
        var png = try XCTUnwrap(files("png").first)
        XCTAssertTrue(png.lastPathComponent.hasPrefix("Amiga-View 20"))
        XCTAssertEqual(CGImage.pngSize(try Data(contentsOf: png)), CGSize(width: 720, height: 576))
        XCTAssertEqual(app.video.status, "Saved \(png.lastPathComponent)")
        try FileManager.default.removeItem(at: png)

        try invoke("Crop Overscan")
        try invoke("Save Snapshot")
        png = try XCTUnwrap(files("png").first)
        XCTAssertEqual(CGImage.pngSize(try Data(contentsOf: png)), CGSize(width: 708, height: 574))
    }

    private func feedFrames() {
        for _ in 0..<8 {
            app.handleFrame(field())
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
    }

    func testStartAndStopRecordingWritesAPlayableMovie() async throws {
        try invoke("Start Recording")
        XCTAssertEqual(try item("Stop Recording").keyEquivalent, "r")
        feedFrames()
        let finished = expectation(description: "finished")
        app.recordingFinished = { _ in finished.fulfill() }
        try invoke("Stop Recording")
        await fulfillment(of: [finished], timeout: 10)
        XCTAssertNoThrow(try item("Start Recording"))
        let mov = try XCTUnwrap(files("mov").first)
        XCTAssertEqual(app.video.status, "Saved \(mov.lastPathComponent)")
        let asset = AVURLAsset(url: mov)
        let video = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(video.count, 1)
        let size = try await video[0].load(.naturalSize), seconds = try await asset.load(.duration).seconds
        XCTAssertEqual(size, CGSize(width: 720, height: 576))
        XCTAssertEqual(seconds, 0.35, accuracy: 0.25)
    }

    /// The Deskflow status used to replace the whole status line, hiding a running recording.
    func testRecordingLineStaysVisibleWhileAmigaHasInput() throws {
        let log = dir.appendingPathComponent("deskflow.log").path
        try "[t] INFO: switch from \"BMS-MAC001\" to \"replay\" at 0,539\n".write(toFile: log, atomically: true, encoding: .utf8)
        app.deskflow = DeskflowMonitor(path: log, clock: { 100 }, trusted: { true }, postRelease: {})
        try invoke("Start Recording")
        app.refreshStatus()
        let lines = app.video.status.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 2, app.video.status)
        XCTAssertTrue(lines[0].hasPrefix("Recording 00:0"), lines[0])
        XCTAssertEqual(lines[1], DeskflowMonitor.amigaStatus)
        // The status text is the only sign: the video has no border (it was cut off in full screen).
        XCTAssertEqual(app.video.layer?.borderWidth ?? 0, 0)

        // Both lines are drawn: the label is two lines tall.
        let label = try XCTUnwrap(app.video.subviews.compactMap { $0 as? NSTextField }.first)
        app.video.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(label.frame.height, label.font!.boundingRectForFont.height * 1.5)

        let finished = expectation(description: "finished")
        app.recordingFinished = { _ in finished.fulfill() }
        try invoke("Stop Recording")
        wait(for: [finished], timeout: 10)
    }
}

private extension CGImage {
    static func pngSize(_ data: Data) -> CGSize {
        let src = CGImageSourceCreateWithData(data as CFData, nil)!
        let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil)! as! [CFString: Any]
        return CGSize(width: p[kCGImagePropertyPixelWidth] as! Int, height: p[kCGImagePropertyPixelHeight] as! Int)
    }
}
