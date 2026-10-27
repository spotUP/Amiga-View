import AppKit
import AmigaViewCore
import LibrashaderBridge
import Metal

/// Shows the newest frame, aspect-fitted, on a Metal layer (see PictureRenderer), plus a status line.
final class VideoView: NSView {
    private let label = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        let layer = metalLayer
        layer.backgroundColor = NSColor.black.cgColor
        layer.pixelFormat = .bgra8Unorm
        // Not framebuffer-only: tests read the drawable back.
        layer.framebufferOnly = false
        layer.isOpaque = true
        // The picture is sRGB; without a colorspace the layer is not colour matched and looks oversaturated on wide-gamut displays.
        layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        if let renderer { layer.device = renderer.device }
        label.textColor = .white
        label.backgroundColor = NSColor.black.withAlphaComponent(0.6)
        label.drawsBackground = true
        label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        label.maximumNumberOfLines = 0
        addSubview(label)
    }

    /// Called on every mouseUp, including that of the click that activates the window. Not on
    /// mouseDown: Deskflow keeps input on the Mac while a button is held, so the edge crossing
    /// switchSynergy posts would be ignored.
    /// Gets the click's location in screen coordinates.
    var onClick: ((CGPoint) -> Void)?

    override func mouseUp(with event: NSEvent) {
        onClick?(window?.convertPoint(toScreen: event.locationInWindow)
                 ?? event.locationInWindow)
        super.mouseUp(with: event)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    static let escapeKeyCode: UInt16 = 53
    /// Called for Esc, the one key the view acts on: full screen is left the way video players
    /// leave it.
    var onEscape: (() -> Void)?

    /// The window takes no input (Synergy carries it to the Amiga), but keys still arrive here:
    /// typing while the window is key.
    /// Unhandled, they reach NSResponder's noResponder and beep, so the view takes them and drops them.
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == Self.escapeKeyCode { onEscape?() }
    }
    override func keyUp(with event: NSEvent) {}
    override func flagsChanged(with event: NSEvent) {}

    required init?(coder: NSCoder) { fatalError("not used") }

    /// The newest field as decoded; snapshots and recordings read it.
    var image: CGImage? {
        didSet {
            frameCount &+= 1
            draw()
        }
    }

    /// The part of the field shown, in field pixels (see ViewGeometry.cropRect).
    var crop = ViewGeometry.fullField {
        didSet { needsLayout = true; draw() }
    }

    var integerScaling = false {
        didSet { needsLayout = true; draw() }
    }

    /// Where the video is drawn, in view coordinates.
    var videoFrame: CGRect {
        let content = ViewGeometry.displaySize(of: crop)
        return integerScaling ? ViewGeometry.integerFit(in: bounds.size, content: content)
                              : ViewGeometry.fit(in: bounds.size, content: content)
    }

    // MARK: CRT shader

    enum ShaderState: Equatable { case off, loading, ready, failed(String) }

    private(set) var shaderState = ShaderState.off {
        didSet { if shaderState != oldValue { onShaderState?(shaderState) } }
    }
    /// Called on the main queue whenever the shader state changes.
    var onShaderState: ((ShaderState) -> Void)?
    /// Test sentinel and measurement hook: the loaded chain, nil while off, loading or failed.
    private(set) var chain: LBFilterChain?
    private var loadGeneration = 0
    /// The newest wanted generation, readable from the load queue so a queued load that is stale skips its compile.
    private let wantedGeneration = WantedGeneration()
    /// Compiles a preset; tests replace it to count compiles.
    var chainLoader: (String, MTLCommandQueue) throws -> LBFilterChain = { try LBFilterChain(presetPath: $0, queue: $1) }
    /// A serial queue: the 15 s cold load must not run beside another load of the same process.
    private let loadQueue = DispatchQueue(label: "CRT shader load", qos: .userInitiated)

    /// The preset to filter the picture with; nil shows the plain picture. Loads on a background
    /// queue and draws plain meanwhile; a load for a preset that is no longer wanted is skipped, or
    /// dropped when already running. Choosing the preset that is active, loading or loaded is a no-op;
    /// a failed one is tried again.
    var shaderPreset: URL? {
        didSet {
            if shaderPreset == oldValue { if case .failed = shaderState {} else { return } }
            loadGeneration += 1
            wantedGeneration.set(loadGeneration)
            chain = nil
            guard let url = shaderPreset, let renderer else { shaderState = .off; draw(); return }
            shaderState = .loading
            let generation = loadGeneration, queue = renderer.queue, wanted = wantedGeneration, load = chainLoader
            loadQueue.async { [weak self] in
                guard wanted.value == generation else { return }
                let result = Result { try load(url.path, queue) }
                DispatchQueue.main.async {
                    guard let self, generation == self.loadGeneration else { return }
                    switch result {
                    case .success(let c): self.chain = c; self.shaderState = .ready
                    case .failure(let e): self.shaderState = .failed(e.localizedDescription)
                    }
                    self.draw()
                }
            }
        }
    }

    // MARK: Drawing

    let renderer = PictureRenderer()
    /// Amiga frames that have arrived; the shader's timing follows it, not the display refresh.
    private var frameCount: UInt = 0

    var metalLayer: CAMetalLayer { layer as! CAMetalLayer }

    override func makeBackingLayer() -> CALayer { CAMetalLayer() }

    private var scale: CGFloat { window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1 }

    /// Where the picture is drawn in the drawable, in pixels.
    var pictureRect: CGRect {
        ViewGeometry.pictureRect(in: bounds.size, scale: scale, crop: crop, integerScaling: integerScaling)
    }

    /// Keeps drawableSize equal to bounds * scale, so no frame is drawn with a rect from the new
    /// bounds into a drawable of the old size.
    private func syncDrawableSize() {
        let layer = metalLayer
        layer.contentsScale = scale
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        if layer.drawableSize != size { layer.drawableSize = size }
    }

    private func draw() {
        syncDrawableSize()
        guard let renderer, let image else { return }
        renderer.render(field: image, crop: crop, rect: pictureRect, chain: chain, frameCount: frameCount, to: metalLayer)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsLayout = true
    }

    var status: String = "" {
        didSet { label.stringValue = status.split(separator: "\n").map { " \($0) " }.joined(separator: "\n"); needsLayout = true }
    }

    override func layout() {
        super.layout()
        draw()
        label.sizeToFit()
        label.frame.origin = NSPoint(x: 8, y: 8)
    }
}

/// An integer shared between the main queue (writer) and the shader load queue (reader).
private final class WantedGeneration {
    private let lock = NSLock()
    private var current = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return current }
    func set(_ v: Int) { lock.lock(); current = v; lock.unlock() }
}
