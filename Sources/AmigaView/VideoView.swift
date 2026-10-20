import AppKit
import AmigaViewCore

/// Shows the newest frame, aspect-fitted, with nearest-neighbour scaling, plus a status line.
final class VideoView: NSView {
    private let videoLayer = CALayer()
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
        addSubview(label)
    }

    /// Called on every mouseDown, including the click that activates the window.
    var onClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onClick?()
        super.mouseDown(with: event)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    required init?(coder: NSCoder) { fatalError("not used") }

    var image: CGImage? {
        didSet {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            videoLayer.contents = image
            CATransaction.commit()
        }
    }

    var status: String = "" {
        didSet { label.stringValue = " " + status + " "; needsLayout = true }
    }

    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        videoLayer.frame = ViewGeometry.fit(in: bounds.size)
        CATransaction.commit()
        label.sizeToFit()
        label.frame.origin = NSPoint(x: 8, y: 8)
    }
}
