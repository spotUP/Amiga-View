import AppKit
import AmigaViewCore
import LibrashaderBridge
import Metal
import QuartzCore

/// Draws the Amiga field into a CAMetalLayer: the cropped field is uploaded at its native size
/// (no CPU line doubling) into one of a ring of reused textures, then either blitted to the drawable or sent
/// through a librashader chain first. All calls come from the main thread: the chain is not
/// thread safe.
final class PictureRenderer {
    let device: MTLDevice
    let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let nearest: MTLSamplerState
    private let linear: MTLSamplerState
    /// Frames that may be on the GPU at once; each reads its own source texture, so the CPU never
    /// overwrites one the GPU still samples. A permit is taken per frame and given back when its command buffer completes.
    static let framesInFlight = 3
    private var sources = [MTLTexture?](repeating: nil, count: framesInFlight)
    private var nextSource = 0
    private let inFlight = DispatchSemaphore(value: framesInFlight)
    /// The source texture the last frame sampled (tests check the ring).
    private(set) var lastSource: MTLTexture?
    private var pixels = [UInt8]()
    private var offscreen: MTLTexture?

    /// The last drawable's texture and the command buffer that filled it (tests read them back).
    private(set) var lastTexture: MTLTexture?
    private(set) var lastCommandBuffer: MTLCommandBuffer?

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;
    struct V { float4 position [[position]]; float2 uv; };
    vertex V pictureVertex(uint i [[vertex_id]]) {
        float2 p = float2((i << 1) & 2, i & 2);
        V v; v.position = float4(p * 2.0 - 1.0, 0.0, 1.0); v.uv = float2(p.x, 1.0 - p.y);
        return v;
    }
    fragment float4 pictureFragment(V v [[stage_in]], texture2d<float> t [[texture(0)]], sampler s [[sampler(0)]]) {
        return t.sample(s, v.uv);
    }
    """

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: Self.shaderSource, options: nil) else { return nil }
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = library.makeFunction(name: "pictureVertex")
        d.fragmentFunction = library.makeFunction(name: "pictureFragment")
        d.colorAttachments[0].pixelFormat = .bgra8Unorm
        func sampler(_ f: MTLSamplerMinMagFilter) -> MTLSamplerState? {
            let s = MTLSamplerDescriptor(); s.minFilter = f; s.magFilter = f
            return device.makeSamplerState(descriptor: s)
        }
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: d),
              let nearest = sampler(.nearest), let linear = sampler(.linear) else { return nil }
        (self.device, self.queue, self.pipeline, self.nearest, self.linear) = (device, queue, pipeline, nearest, linear)
    }

    /// Copies `crop` (field pixels) of `field` into the next texture of the source ring.
    private func upload(_ field: CGImage, crop: CGRect) -> MTLTexture? {
        let r = crop.integral.intersection(CGRect(x: 0, y: 0, width: field.width, height: field.height))
        guard !r.isNull, r.width > 0, r.height > 0, let part = field.cropping(to: r) else { return nil }
        let (w, h) = (part.width, part.height)
        if pixels.count != w * h * 4 { pixels = [UInt8](repeating: 0, count: w * h * 4) }
        let slot = nextSource
        if sources[slot]?.width != w || sources[slot]?.height != h {
            sources[slot] = makeTexture(w, h, usage: .shaderRead, storage: .shared)
        }
        guard let source = sources[slot] else { return nil }
        let drawn = pixels.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            else { return false }
            ctx.interpolationQuality = .none
            ctx.draw(part, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        source.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: pixels, bytesPerRow: w * 4)
        nextSource = (slot + 1) % Self.framesInFlight
        return source
    }

    private func makeTexture(_ w: Int, _ h: Int, usage: MTLTextureUsage, storage: MTLStorageMode = .private) -> MTLTexture? {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        d.usage = usage
        d.storageMode = storage
        return device.makeTexture(descriptor: d)
    }

    /// Draws `crop` of `field` into `rect` (pixels) of the layer's next drawable. With a `chain`
    /// the picture first goes through it at `ViewGeometry.chainSize`, then one linear pass scales
    /// it to `rect`; a chain error shows the plain picture for that frame. Returns false when
    /// nothing was drawn.
    @discardableResult
    func render(field: CGImage, crop: CGRect, rect: CGRect, chain: LBFilterChain?, frameCount: UInt, to layer: CAMetalLayer) -> Bool {
        guard rect.width > 0, rect.height > 0, layer.drawableSize.width >= 1, layer.drawableSize.height >= 1,
              let cb = queue.makeCommandBuffer(), let drawable = layer.nextDrawable() else { return false }
        // A stalled GPU gives up the frame after a second instead of freezing the main thread.
        guard inFlight.wait(timeout: .now() + 1) == .success else { return false }
        var committed = false
        defer { if !committed { inFlight.signal() } }
        guard let src = upload(field, crop: crop) else { return false }
        lastSource = src
        var picture = src, filter = nearest
        if let chain {
            let size = ViewGeometry.chainSize(for: rect.size)
            let (w, h) = (Int(size.width), Int(size.height))
            if offscreen?.width != w || offscreen?.height != h { offscreen = makeTexture(w, h, usage: [.renderTarget, .shaderRead]) }
            if let target = offscreen,
               (try? chain.renderSource(src, toTarget: target, commandBuffer: cb,
                                        viewport: CGRect(x: 0, y: 0, width: w, height: h), frameCount: frameCount)) != nil {
                picture = target; filter = linear
            }
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        pass.colorAttachments[0].storeAction = .store
        guard let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return false }
        enc.setViewport(MTLViewport(originX: Double(rect.minX), originY: Double(rect.minY), width: Double(rect.width),
                                    height: Double(rect.height), znear: 0, zfar: 1))
        enc.setRenderPipelineState(pipeline)
        enc.setFragmentTexture(picture, index: 0)
        enc.setFragmentSamplerState(filter, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        cb.present(drawable)
        cb.addCompletedHandler { [inFlight] _ in inFlight.signal() }
        committed = true
        cb.commit()
        lastTexture = drawable.texture
        lastCommandBuffer = cb
        return true
    }
}
