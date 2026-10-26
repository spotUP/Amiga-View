import AppKit
import XCTest
@testable import AmigaView
@testable import AmigaViewCore

@MainActor
final class PictureMenuTests: XCTestCase {
    private var app: AppDelegate!
    private var suite = ""

    override func setUp() {
        _ = NSApplication.shared
        suite = "menu-tests-" + UUID().uuidString
        app = AppDelegate()
        app.defaults = UserDefaults(suiteName: suite)!
        app.frameAutosaveName = nil
        app.buildWindow()
        app.window.setFrameOrigin(NSPoint(x: 100, y: 100))
        app.buildMenu()
    }

    override func tearDown() {
        UserDefaults(suiteName: suite)!.removePersistentDomain(forName: suite)
    }

    private func item(_ title: String) throws -> NSMenuItem {
        try XCTUnwrap(NSApp.mainMenu?.items.compactMap(\.submenu).flatMap(\.items).first { $0.title == title }, title)
    }

    private func invoke(_ title: String) throws {
        let i = try item(title)
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(i.action), to: i.target, from: i))
    }

    /// Crop Overscan and Integer Scaling change what the view draws and the window's aspect.
    func testCropAndIntegerScaling() throws {
        let video = app.video, window = app.window!
        window.setContentSize(NSSize(width: 1500, height: 1200))
        XCTAssertEqual(video.videoLayer.contentsRect, CGRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertEqual(window.contentAspectRatio, ViewGeometry.actualSize)

        try invoke("Crop Overscan")
        XCTAssertEqual(video.videoLayer.contentsRect, ViewGeometry.contentsRect(for: ViewGeometry.defaultCrop))
        XCTAssertEqual(window.contentAspectRatio, CGSize(width: 708, height: 574))
        XCTAssertEqual(try item("Crop Overscan").state, .on)
        XCTAssertTrue(PictureOption.cropOverscan.isEnabled(in: app.defaults))

        video.frame = NSRect(x: 0, y: 0, width: 1500, height: 1200); video.layoutSubtreeIfNeeded()
        let fitted = video.videoFrame
        XCTAssertNotEqual(fitted.width.truncatingRemainder(dividingBy: 708), 0)   // fractional scale

        try invoke("Integer Scaling")
        video.layoutSubtreeIfNeeded()
        XCTAssertEqual(video.videoFrame, CGRect(x: 42, y: 26, width: 1416, height: 1148))

        try invoke("Integer Scaling"); try invoke("Crop Overscan")
        XCTAssertEqual(video.videoLayer.contentsRect, CGRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertEqual(window.contentAspectRatio, ViewGeometry.actualSize)
    }

    func testScanlinesLayer() throws {
        let video = app.video
        XCTAssertNil(video.scanlineLayer.superlayer)
        try invoke("Scanlines")
        XCTAssertTrue(video.scanlineLayer.superlayer === video.layer)
        XCTAssertEqual((video.scanlineLayer.contents as! CGImage).height, 576)
        XCTAssertEqual(video.scanlineLayer.frame, video.videoLayer.frame)
        try invoke("Crop Overscan")
        XCTAssertEqual((video.scanlineLayer.contents as! CGImage).height, 574)
        try invoke("Scanlines")
        XCTAssertNil(video.scanlineLayer.superlayer)
    }

    func testFullScreenItemAndCollectionBehavior() throws {
        XCTAssertTrue(app.window.collectionBehavior.contains(.fullScreenPrimary))
        let i = try item("Enter Full Screen")
        XCTAssertEqual(i.action, #selector(NSWindow.toggleFullScreen(_:)))
        XCTAssertEqual(i.keyEquivalent, "f")
        XCTAssertEqual(i.keyEquivalentModifierMask, [.control, .command])
    }

    /// Full screen hides the window buttons: entering it says how to leave, and Esc leaves it.
    func testEscLeavesFullScreenAndEnteringSaysHow() {
        var fullScreen = false, exits = 0
        app.isFullScreen = { fullScreen }
        app.exitFullScreen = { exits += 1 }
        func esc() -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                             windowNumber: app.window.windowNumber, context: nil, characters: "\u{1b}",
                             charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: VideoView.escapeKeyCode)!
        }
        app.video.keyDown(with: esc())
        XCTAssertEqual(exits, 0)

        NotificationCenter.default.post(name: NSWindow.didEnterFullScreenNotification, object: app.window)
        XCTAssertEqual(app.video.status, AppDelegate.fullScreenHint)
        fullScreen = true
        app.video.keyDown(with: esc())
        XCTAssertEqual(exits, 1)
    }

    /// A click near the right edge of the desktop is ignored; a click elsewhere switches.
    func testClickNearTheEdgeDoesNotSwitch() {
        var switches = 0
        app.performSwitch = { switches += 1 }
        app.accessibilityTrusted = true
        app.edgeGuard.desktop = { CGRect(x: 0, y: 0, width: 1630, height: 1200) }
        app.window.delegate = nil
        app.window.setFrame(NSRect(x: 900, y: 100, width: 720, height: 576), display: false)
        app.video.onClick = { [weak self] in self?.app.switchSynergy(clickAt: $0) }
        func click(atWindowX x: CGFloat) {
            let e = NSEvent.mouseEvent(with: .leftMouseUp, location: NSPoint(x: x, y: 50), modifierFlags: [], timestamp: 0,
                                       windowNumber: app.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
            app.video.mouseUp(with: e)
        }
        click(atWindowX: 715)       // screen x 1615, within 16 of 1630
        XCTAssertEqual(switches, 0)
        click(atWindowX: 100)
        XCTAssertEqual(switches, 1)
    }
}
