import AppKit
import Metal
import XCTest
import LibrashaderBridge
@testable import AmigaView
@testable import AmigaViewCore

@MainActor
final class PictureRendererTests: XCTestCase {
    private static let shaders = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/shaders")
    private static let preset = shaders.appendingPathComponent("bezel/Mega_Bezel/Presets/MBZ__3__STD.slangp")

    private func field() throws -> CGImage {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 720, height: 288, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue))
        ctx.setFillColor(CGColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 720, height: 288))
        return try XCTUnwrap(ctx.makeImage())
    }

    private func layer(_ r: PictureRenderer) -> CAMetalLayer {
        let l = CAMetalLayer()
        l.device = r.device; l.pixelFormat = .bgra8Unorm
        l.drawableSize = CGSize(width: 720, height: 576)
        return l
    }

    /// Each frame uploads into the next texture of a ring, so the CPU never overwrites a texture an
    /// earlier frame still samples; frames that draw nothing give their permit back, so later frames still draw.
    func testSourceTexturesRotateAndFailedFramesKeepThePermits() throws {
        let renderer = try XCTUnwrap(PictureRenderer(), "no Metal device")
        let l = layer(renderer), f = try field(), rect = CGRect(x: 0, y: 0, width: 720, height: 576)
        var used = [ObjectIdentifier]()
        for _ in 0..<PictureRenderer.framesInFlight * 2 {
            XCTAssertTrue(renderer.render(field: f, crop: ViewGeometry.fullField, rect: rect, chain: nil, frameCount: 0, to: l))
            used.append(ObjectIdentifier(try XCTUnwrap(renderer.lastSource)))
            try XCTUnwrap(renderer.lastCommandBuffer).waitUntilCompleted()
        }
        XCTAssertEqual(Set(used).count, PictureRenderer.framesInFlight)
        XCTAssertEqual(Array(used[0..<3]), Array(used[3..<6]))
        // A crop outside the field uploads nothing; more of those than permits must not exhaust them.
        for _ in 0..<PictureRenderer.framesInFlight * 2 {
            XCTAssertFalse(renderer.render(field: f, crop: CGRect(x: 5000, y: 5000, width: 10, height: 10), rect: rect, chain: nil, frameCount: 0, to: l))
        }
        XCTAssertTrue(renderer.render(field: f, crop: ViewGeometry.fullField, rect: rect, chain: nil, frameCount: 0, to: l))
    }

    /// Choosing presets A, B, C while A compiles runs only A and C; choosing the active one compiles nothing.
    func testStalePresetLoadsAreSkippedAndReselectingIsANoOp() throws {
        let video = VideoView(frame: NSRect(x: 0, y: 0, width: 720, height: 576))
        try XCTSkipIf(video.renderer == nil, "no Metal device")
        let lock = NSLock(), started = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        var loaded = [String]()
        video.chainLoader = { path, queue in
            lock.lock(); loaded.append(path); let first = loaded.count == 1; lock.unlock()
            if first { started.signal(); release.wait() }
            return try LBFilterChain(presetPath: path, queue: queue)
        }
        let a = Self.preset
        let b = Self.shaders.appendingPathComponent("b.slangp")
        let c = Self.shaders.appendingPathComponent("bezel/Mega_Bezel/Presets/../Presets/MBZ__3__STD.slangp")
        video.shaderPreset = a
        XCTAssertEqual(started.wait(timeout: .now() + 10), .success)
        video.shaderPreset = b
        video.shaderPreset = c
        video.shaderPreset = c      // already loading
        release.signal()
        let deadline = Date().addingTimeInterval(60)
        while video.chain == nil, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        XCTAssertEqual(video.shaderState, .ready)
        lock.lock(); XCTAssertEqual(loaded, [a.path, c.path]); lock.unlock()

        let ready = video.chain
        video.shaderPreset = c      // already active
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertTrue(video.chain === ready)
        XCTAssertEqual(video.shaderState, .ready)
        lock.lock(); XCTAssertEqual(loaded.count, 2); lock.unlock()
    }

    /// With a shader chain the picture fills the whole drawable: the preset places the screen and
    /// draws its bezel around it. Without one it keeps the (integer) fit.
    func testShaderChainDrawsIntoTheWholeDrawable() throws {
        let video = VideoView(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
        try XCTSkipIf(video.renderer == nil, "no Metal device")
        video.integerScaling = true
        video.image = try field()
        let scale = video.metalLayer.contentsScale
        let fitted = ViewGeometry.pictureRect(in: video.bounds.size, scale: scale, crop: video.crop, integerScaling: true)
        XCTAssertEqual(video.pictureRect, fitted)
        video.shaderPreset = Self.preset
        let deadline = Date().addingTimeInterval(30)
        while video.chain == nil, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        XCTAssertEqual(video.shaderState, .ready)
        XCTAssertEqual(video.pictureRect, CGRect(x: 0, y: 0, width: 1000 * scale, height: 700 * scale))
        video.shaderPreset = nil
        XCTAssertEqual(video.pictureRect, fitted)
    }

    /// A frame after a bounds change and before layout still draws into a drawable of the new size.
    func testDrawableSizeFollowsBoundsAtDrawTime() throws {
        let video = VideoView(frame: NSRect(x: 0, y: 0, width: 720, height: 576))
        try XCTSkipIf(video.renderer == nil, "no Metal device")
        video.layoutSubtreeIfNeeded()
        video.image = try field()
        video.setFrameSize(NSSize(width: 300, height: 200))
        video.image = try field()
        let scale = video.metalLayer.contentsScale
        XCTAssertEqual(video.metalLayer.drawableSize, CGSize(width: 300 * scale, height: 200 * scale))
    }

    func testLayerIsColourMatchedToSRGB() throws {
        let video = VideoView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertEqual(video.metalLayer.colorspace?.name as String?, CGColorSpace.sRGB as String)
    }
}
