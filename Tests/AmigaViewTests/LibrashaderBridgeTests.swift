import Metal
import XCTest
import LibrashaderBridge
@testable import AmigaViewCore

/// Spike: can a librashader Metal chain load a Mega Bezel reflection preset and render frames?
final class LibrashaderBridgeTests: XCTestCase {
    /// The Mega Bezel preset from build/shaders, found the way the app finds it under swift build.
    static let preset = CRTShader.shadersURL(bundle: Bundle(for: LibrashaderBridgeTests.self))
        .appendingPathComponent(CRTShader.standard.presetPath).path

    func testMegaBezelReflectionPresetRendersThreeFrames() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: Self.preset),
                          "\(Self.preset) is missing; run scripts/fetch-shaders.sh")
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw XCTSkip("no Metal device")
        }
        let (sw, sh, tw, th) = (720, 288, 1440, 1080)

        let sd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: sw, height: sh, mipmapped: false)
        sd.usage = [.shaderRead]
        let source = try XCTUnwrap(device.makeTexture(descriptor: sd))
        var pixels = [UInt8](repeating: 0, count: sw * sh * 4)
        for y in 0..<sh { for x in 0..<sw {
            let i = (y * sw + x) * 4
            pixels[i] = UInt8(x * 255 / sw); pixels[i + 1] = UInt8(y * 255 / sh)
            pixels[i + 2] = ((x / 24 + y / 24) % 2 == 0) ? 255 : 40; pixels[i + 3] = 255
        } }
        source.replace(region: MTLRegionMake2D(0, 0, sw, sh), mipmapLevel: 0, withBytes: pixels, bytesPerRow: sw * 4)

        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: tw, height: th, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]
        td.storageMode = .shared
        let target = try XCTUnwrap(device.makeTexture(descriptor: td))

        let t0 = CFAbsoluteTimeGetCurrent()
        let chain = try LBFilterChain(presetPath: Self.preset, queue: queue)
        let loadMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        print("LIBRASHADER preset load: \(Int(loadMs)) ms")

        var gpuMs: [Double] = []
        for frame in 0..<3 {
            let cb = try XCTUnwrap(queue.makeCommandBuffer())
            try chain.renderSource(source, toTarget: target, commandBuffer: cb,
                                   viewport: CGRect(x: 0, y: 0, width: tw, height: th), frameCount: UInt(frame))
            cb.commit()
            cb.waitUntilCompleted()
            XCTAssertEqual(cb.status, .completed, "\(String(describing: cb.error))")
            gpuMs.append((cb.gpuEndTime - cb.gpuStartTime) * 1000)
        }
        print("LIBRASHADER GPU ms per frame: \(gpuMs.map { String(format: "%.2f", $0) })")
        XCTAssertEqual(chain.frameCallCount, 3)

        var out = [UInt8](repeating: 0, count: tw * th * 4)
        target.getBytes(&out, bytesPerRow: tw * 4, from: MTLRegionMake2D(0, 0, tw, th), mipmapLevel: 0)
        let first = Array(out[0..<4])
        let distinct = stride(from: 0, to: out.count, by: 4).contains { Array(out[$0..<$0 + 4]) != first }
        XCTAssertTrue(distinct, "target is a single colour")
    }

    /// R9: a preset loaded from librashader's shader cache skips glslang and SPIRV-Cross, so it
    /// loads in well under a third of the time a full compile takes, and renders the same picture.
    func testShaderCacheMakesAReloadFastAndRendersTheSamePicture() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: Self.preset),
                          "\(Self.preset) is missing; run scripts/fetch-shaders.sh")
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw XCTSkip("no Metal device")
        }
        func load(cache: Bool) throws -> (LBFilterChain, Double) {
            let t0 = CFAbsoluteTimeGetCurrent()
            let chain = try LBFilterChain(presetPath: Self.preset, queue: queue, shaderCache: cache)
            return (chain, (CFAbsoluteTimeGetCurrent() - t0) * 1000)
        }
        let (compiled, compileMs) = try load(cache: false)
        _ = try load(cache: true)                  // fills the cache if this pass is not in it yet
        let (cached, cachedMs) = try load(cache: true)
        print("LIBRASHADER load: compiled \(Int(compileMs)) ms, cached \(Int(cachedMs)) ms")

        let db = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/librashader/librashader.db.1")
        XCTAssertTrue(FileManager.default.fileExists(atPath: db.path), "no shader cache at \(db.path)")
        XCTAssertLessThan(cachedMs, compileMs / 3, "cached load is not fast")
        let same = try render(compiled, device: device, queue: queue) == render(cached, device: device, queue: queue)
        XCTAssertTrue(same, "cached passes render a different picture")
    }

    /// Renders three frames of a test pattern through `chain` and returns the last frame's pixels.
    private func render(_ chain: LBFilterChain, device: MTLDevice, queue: MTLCommandQueue) throws -> [UInt8] {
        let (sw, sh, tw, th) = (360, 144, 720, 540)
        let sd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: sw, height: sh, mipmapped: false)
        sd.usage = [.shaderRead]
        let source = try XCTUnwrap(device.makeTexture(descriptor: sd))
        var pixels = [UInt8](repeating: 0, count: sw * sh * 4)
        for y in 0..<sh { for x in 0..<sw {
            let i = (y * sw + x) * 4
            pixels[i] = UInt8(x * 255 / sw); pixels[i + 1] = UInt8(y * 255 / sh)
            pixels[i + 2] = ((x / 12 + y / 12) % 2 == 0) ? 255 : 40; pixels[i + 3] = 255
        } }
        source.replace(region: MTLRegionMake2D(0, 0, sw, sh), mipmapLevel: 0, withBytes: pixels, bytesPerRow: sw * 4)
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: tw, height: th, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]
        td.storageMode = .shared
        let target = try XCTUnwrap(device.makeTexture(descriptor: td))
        for frame in 0..<3 {
            let cb = try XCTUnwrap(queue.makeCommandBuffer())
            try chain.renderSource(source, toTarget: target, commandBuffer: cb,
                                   viewport: CGRect(x: 0, y: 0, width: tw, height: th), frameCount: UInt(frame))
            cb.commit()
            cb.waitUntilCompleted()
        }
        var out = [UInt8](repeating: 0, count: tw * th * 4)
        target.getBytes(&out, bytesPerRow: tw * 4, from: MTLRegionMake2D(0, 0, tw, th), mipmapLevel: 0)
        return out
    }
}
