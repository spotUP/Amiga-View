import AppKit
import Metal
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
        XCTAssertEqual(video.crop, ViewGeometry.fullField)
        XCTAssertEqual(window.contentAspectRatio, ViewGeometry.actualSize)

        try invoke("Crop Overscan")
        XCTAssertEqual(video.crop, ViewGeometry.defaultCrop)
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
        XCTAssertEqual(video.crop, ViewGeometry.fullField)
        XCTAssertEqual(window.contentAspectRatio, ViewGeometry.actualSize)
    }

    private func shaderItem(_ title: String) throws -> NSMenuItem {
        let menu = try XCTUnwrap(try item("CRT Shader").submenu)
        return try XCTUnwrap(menu.items.first { $0.title == title }, title)
    }

    private func readPixel(_ video: VideoView) throws -> [UInt8] {
        let r = try XCTUnwrap(video.renderer)
        try XCTUnwrap(r.lastCommandBuffer).waitUntilCompleted()
        let t = try XCTUnwrap(r.lastTexture)
        var px = [UInt8](repeating: 0, count: 4)
        t.getBytes(&px, bytesPerRow: 4, from: MTLRegionMake2D(t.width / 2, t.height / 2, 1, 1), mipmapLevel: 0)
        return px
    }

    /// Reachability: the CRT Shader menu item loads a preset, the next Amiga frame goes through the
    /// librashader chain (frameCallCount is the sentinel), and the drawn pixel differs from the plain
    /// picture. The fixture preset is one pass that inverts the colour.
    func testCRTShaderMenuDrivesTheFilterChain() throws {
        try XCTSkipIf(app.video.renderer == nil, "no Metal device")
        app.shadersURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/shaders")
        app.window.setContentSize(NSSize(width: 720, height: 576))
        app.video.frame = NSRect(x: 0, y: 0, width: 720, height: 576)
        app.video.layoutSubtreeIfNeeded()

        let ctx = try XCTUnwrap(CGContext(data: nil, width: 720, height: 288, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue))
        ctx.setFillColor(CGColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 720, height: 288))
        let field = try XCTUnwrap(ctx.makeImage())

        let standard = try shaderItem("Standard")      // no frame yet: loading draws nothing
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(standard.action), to: standard.target, from: standard))
        XCTAssertEqual(standard.state, .on)
        XCTAssertNil(app.video.chain)
        let deadline = Date().addingTimeInterval(60)
        while app.video.chain == nil, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        let chain = try XCTUnwrap(app.video.chain, "preset did not load: \(app.video.shaderState)")
        XCTAssertEqual(chain.frameCallCount, 0)

        app.handleFrame(field)
        XCTAssertEqual(chain.frameCallCount, 1)
        let filtered = try readPixel(app.video)

        let off = try shaderItem("Off")
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(off.action), to: off.target, from: off))
        XCTAssertNil(app.video.chain)
        XCTAssertEqual(chain.frameCallCount, 1)
        let plain = try readPixel(app.video)
        XCTAssertNotEqual(filtered, plain)
        // BGRA: the plain picture keeps 0.6 blue; the fixture shader inverts it to 0.4.
        XCTAssertEqual(Double(plain[0]), 0.6 * 255, accuracy: 3)
        XCTAssertEqual(Double(filtered[0]), 0.4 * 255, accuracy: 3)
    }

    func testFullScreenItemAndCollectionBehavior() throws {
        XCTAssertTrue(app.window.collectionBehavior.contains(.fullScreenPrimary))
        let i = try item("Enter Full Screen")
        XCTAssertEqual(i.action, #selector(NSWindow.toggleFullScreen(_:)))
        XCTAssertEqual(i.keyEquivalent, "f")
        XCTAssertEqual(i.keyEquivalentModifierMask, [.control, .command])
    }

    /// Cmd-Return toggles full screen too, the way emulators do, through a hidden View menu item.
    func testCommandReturnTogglesFullScreen() throws {
        let i = try XCTUnwrap(NSApp.mainMenu?.items.compactMap(\.submenu).flatMap(\.items)
            .first { $0.keyEquivalent == "\r" && $0.keyEquivalentModifierMask == .command })
        XCTAssertEqual(i.action, #selector(NSWindow.toggleFullScreen(_:)))
        XCTAssertTrue(i.isHidden)
        XCTAssertTrue(i.allowsKeyEquivalentWhenHidden)
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
