// Draws the Amiga-View app icon: a Commodore-style monitor showing the Boing ball on a
// Workbench-blue tile. Run as `swift scripts/make-icon.swift <dir>.iconset`; it writes every
// size iconutil needs. scripts/bundle.sh turns the set into AppIcon.icns.
import AppKit
import CoreGraphics

let canvas: CGFloat = 1024

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// A rect given from the top-left corner, as icon layouts are measured.
func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
    CGRect(x: x, y: canvas - y - h, width: w, height: h)
}

func fillGradient(_ ctx: CGContext, _ path: CGPath, top: CGColor, bottom: CGColor) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [top, bottom] as CFArray,
                              locations: [0, 1])!
    let rect = path.boundingBox
    ctx.drawLinearGradient(gradient, start: CGPoint(x: rect.midX, y: rect.maxY),
                           end: CGPoint(x: rect.midX, y: rect.minY), options: [])
    ctx.restoreGState()
}

/// The Boing ball, ray-traced per pixel so the checkers wrap the sphere.
func boingBall(radius r: Int) -> CGImage {
    let size = r * 2
    var pixels = [UInt8](repeating: 0, count: size * size * 4)
    let tilt = -0.30, spin = 0.35
    let light = { () -> (Double, Double, Double) in
        let v = (-0.45, 0.55, 0.70), len = (v.0 * v.0 + v.1 * v.1 + v.2 * v.2).squareRoot()
        return (v.0 / len, v.1 / len, v.2 / len)
    }()
    for row in 0..<size {
        for col in 0..<size {
            let nx = (Double(col) + 0.5 - Double(r)) / Double(r)
            let ny = (Double(r) - Double(row) - 0.5) / Double(r)
            let dist = (nx * nx + ny * ny).squareRoot()
            let coverage = min(max((1 - dist) * Double(r), 0), 1)
            if coverage <= 0 { continue }
            let nz = max(0, 1 - nx * nx - ny * ny).squareRoot()
            let x1 = nx * cos(tilt) - ny * sin(tilt), y1 = nx * sin(tilt) + ny * cos(tilt)
            let x2 = x1 * cos(spin) + nz * sin(spin), z2 = -x1 * sin(spin) + nz * cos(spin)
            let lat = asin(max(-1, min(1, y1))), lon = atan2(x2, z2)
            let cell = Double.pi / 8
            let red = (Int(floor(lon / cell)) + Int(floor(lat / cell))) & 1 == 0
            let lambert = max(0, nx * light.0 + ny * light.1 + nz * light.2)
            let shade = 0.30 + 0.70 * lambert
            let specular = pow(max(0, 2 * lambert * nz - light.2), 24) * 0.55
            let base: (Double, Double, Double) = red ? (0.88, 0.07, 0.07) : (0.97, 0.97, 0.97)
            let i = (row * size + col) * 4
            for (k, channel) in [base.0, base.1, base.2].enumerated() {
                let value = min(1, channel * shade + specular)
                pixels[i + k] = UInt8(value * coverage * 255)  // premultiplied
            }
            pixels[i + 3] = UInt8(coverage * 255)
        }
    }
    let provider = CGDataProvider(data: Data(pixels) as CFData)!
    return CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
                   space: CGColorSpaceCreateDeviceRGB(),
                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                   provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
}

func drawIcon(_ ctx: CGContext) {
    // Tile on Apple's icon grid, with its drop shadow.
    let tile = CGPath(roundedRect: box(100, 100, 824, 824), cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 24, color: rgb(0x000000, 0.35))
    ctx.addPath(tile)
    ctx.setFillColor(rgb(0x0A2F6B))
    ctx.fillPath()
    ctx.restoreGState()
    fillGradient(ctx, tile, top: rgb(0x3A7BE0), bottom: rgb(0x0A2F6B))

    // Monitor stand, then the beige case over it.
    let stand = CGMutablePath()
    stand.move(to: CGPoint(x: 420, y: canvas - 700))
    stand.addLine(to: CGPoint(x: 604, y: canvas - 700))
    stand.addLine(to: CGPoint(x: 660, y: canvas - 800))
    stand.addLine(to: CGPoint(x: 364, y: canvas - 800))
    stand.closeSubpath()
    fillGradient(ctx, stand, top: rgb(0xB9AF95), bottom: rgb(0x8F866F))

    let body = CGPath(roundedRect: box(190, 215, 644, 500), cornerWidth: 56, cornerHeight: 56, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 22, color: rgb(0x000000, 0.40))
    ctx.addPath(body)
    ctx.setFillColor(rgb(0xD8D0B8))
    ctx.fillPath()
    ctx.restoreGState()
    fillGradient(ctx, body, top: rgb(0xF2ECDA), bottom: rgb(0xC9C0A6))

    // Screen: Boing backdrop, grey with a purple grid.
    let screenRect = box(240, 260, 544, 380)
    let screen = CGPath(roundedRect: screenRect, cornerWidth: 34, cornerHeight: 34, transform: nil)
    ctx.saveGState()
    ctx.addPath(screen)
    ctx.clip()
    ctx.setFillColor(rgb(0xB4B4BC))
    ctx.fill(screenRect)
    ctx.setStrokeColor(rgb(0x9A3FA0))
    ctx.setLineWidth(5)
    let step: CGFloat = 38
    var x = screenRect.minX + 25
    while x < screenRect.maxX { ctx.move(to: CGPoint(x: x, y: screenRect.minY)); ctx.addLine(to: CGPoint(x: x, y: screenRect.maxY)); x += step }
    var y = screenRect.minY + 18
    while y < screenRect.maxY { ctx.move(to: CGPoint(x: screenRect.minX, y: y)); ctx.addLine(to: CGPoint(x: screenRect.maxX, y: y)); y += step }
    ctx.strokePath()

    // Ball with its shadow on the backdrop.
    let radius = 138
    let center = CGPoint(x: screenRect.midX - 18, y: screenRect.midY + 6)
    ctx.setFillColor(rgb(0x2A2030, 0.40))
    ctx.fillEllipse(in: CGRect(x: center.x - CGFloat(radius) + 34, y: center.y - CGFloat(radius) - 22,
                               width: CGFloat(radius * 2), height: CGFloat(radius * 2)))
    ctx.draw(boingBall(radius: radius), in: CGRect(x: center.x - CGFloat(radius), y: center.y - CGFloat(radius),
                                                   width: CGFloat(radius * 2), height: CGFloat(radius * 2)))

    // Glass: a soft highlight across the top and a darker rim.
    let glass = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: [rgb(0xFFFFFF, 0.22), rgb(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(glass, start: CGPoint(x: screenRect.midX, y: screenRect.maxY),
                           end: CGPoint(x: screenRect.midX, y: screenRect.midY), options: [])
    ctx.restoreGState()
    ctx.addPath(screen)
    ctx.setStrokeColor(rgb(0x5E5848))
    ctx.setLineWidth(10)
    ctx.strokePath()

    // Power light on the chin.
    ctx.setFillColor(rgb(0x2BD65A))
    ctx.fillEllipse(in: box(754, 667, 22, 22))
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write("usage: make-icon.swift <output>.iconset\n".data(using: .utf8)!)
    exit(2)
}
let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let master = CGContext(data: nil, width: Int(canvas), height: Int(canvas), bitsPerComponent: 8, bytesPerRow: 0,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
drawIcon(master)
let masterImage = master.makeImage()!

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .high
        ctx.draw(masterImage, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try rep.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent(name))
    }
}
