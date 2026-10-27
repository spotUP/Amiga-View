import AppKit
import AmigaViewCore

/// Shows the newest frame, aspect-fitted, with nearest-neighbour scaling, plus a status line.
final class VideoView: NSView {
    let videoLayer = CALayer()
    /// Darkens the second display row of every field line; present only while Scanlines is on.
    let scanlineLayer = CALayer()
    private let label = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        videoLayer.magnificationFilter = .nearest
        videoLayer.minificationFilter = .linear
        videoLayer.contentsGravity = .resize
        layer?.addSublayer(videoLayer)
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

    var image: CGImage? {
        didSet {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            videoLayer.contents = image
            CATransaction.commit()
        }
    }

    /// The part of the field shown, in field pixels (see ViewGeometry.cropRect).
    var crop = ViewGeometry.fullField {
        didSet { applyPicture() }
    }

    var integerScaling = false {
        didSet { needsLayout = true }
    }

    var scanlines = false {
        didSet { applyPicture() }
    }

    /// Where the video is drawn, in view coordinates.
    var videoFrame: CGRect { videoLayer.frame }

    private func applyPicture() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        videoLayer.contentsRect = ViewGeometry.contentsRect(for: crop)
        if scanlines {
            scanlineLayer.contents = Self.scanlineImage(fieldLines: Int(crop.height))
            scanlineLayer.magnificationFilter = .nearest
            scanlineLayer.minificationFilter = .nearest
            scanlineLayer.contentsGravity = .resize
            if scanlineLayer.superlayer == nil { layer?.insertSublayer(scanlineLayer, above: videoLayer) }
        } else {
            scanlineLayer.removeFromSuperlayer()
            scanlineLayer.contents = nil
        }
        CATransaction.commit()
        needsLayout = true
    }

    /// One pixel wide, two rows per field line, black with the alphas of ViewGeometry.scanlineAlphas.
    static func scanlineImage(fieldLines: Int) -> CGImage? {
        let alphas = ViewGeometry.scanlineAlphas(fieldLines: fieldLines)
        guard !alphas.isEmpty else { return nil }
        guard let ctx = CGContext(data: nil, width: 1, height: alphas.count, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        for (i, a) in alphas.enumerated() {   // row 0 is the top; CGContext's origin is the bottom
            ctx.setFillColor(CGColor(gray: 0, alpha: a))
            ctx.fill(CGRect(x: 0, y: alphas.count - 1 - i, width: 1, height: 1))
        }
        return ctx.makeImage()
    }

    var status: String = "" {
        didSet { label.stringValue = status.split(separator: "\n").map { " \($0) " }.joined(separator: "\n"); needsLayout = true }
    }

    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let content = ViewGeometry.displaySize(of: crop)
        videoLayer.frame = integerScaling ? ViewGeometry.integerFit(in: bounds.size, content: content)
                                          : ViewGeometry.fit(in: bounds.size, content: content)
        scanlineLayer.frame = videoLayer.frame
        CATransaction.commit()
        label.sizeToFit()
        label.frame.origin = NSPoint(x: 8, y: 8)
    }
}
