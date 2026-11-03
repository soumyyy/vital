// Renders Vital's app icon into an .iconset folder: a bold white heartbeat line on a graphite
// continuous-corner squircle with a light glass rim. Same motif as the menu bar glyph.
// Usage: swift Scripts/make-icon.swift build/AppIcon.iconset && iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
import AppKit

/// Continuous-corner squircle (superellipse), close to the macOS app icon shape.
func squircle(_ r: NSRect, n: CGFloat = 5) -> NSBezierPath {
    let p = NSBezierPath()
    let a = r.width / 2, b = r.height / 2
    for i in 0...720 {
        let t = CGFloat(i) * .pi / 360
        let c = cos(t), s = sin(t)
        let pt = NSPoint(x: r.midX + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n),
                         y: r.midY + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n))
        i == 0 ? p.move(to: pt) : p.line(to: pt)
    }
    p.close()
    return p
}

func rgb(_ h: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((h >> 16) & 255) / 255, green: CGFloat((h >> 8) & 255) / 255,
            blue: CGFloat(h & 255) / 255, alpha: a)
}

/// Fills the stroke outline of `path` with a vertical white gradient (a rim that catches light at the top).
func rim(_ path: NSBezierPath, width: CGFloat, in rect: NSRect, top: CGFloat, bottom: CGFloat) {
    let cg = NSGraphicsContext.current!.cgContext
    cg.saveGState()
    cg.addPath(path.cgPath); cg.setLineWidth(width); cg.replacePathWithStrokedPath(); cg.clip()
    NSGradient(colors: [NSColor.white.withAlphaComponent(top), NSColor.white.withAlphaComponent(bottom)])!
        .draw(in: rect, angle: -90)
    cg.restoreGState()
}

func shadow(_ alpha: CGFloat, blur: CGFloat, dy: CGFloat, _ body: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let s = NSShadow()
    s.shadowColor = NSColor.black.withAlphaComponent(alpha); s.shadowBlurRadius = blur
    s.shadowOffset = NSSize(width: 0, height: dy)
    s.set()
    body()
    NSGraphicsContext.restoreGraphicsState()
}

func render(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let t = NSAffineTransform(); t.scale(by: CGFloat(pixels) / 1024); t.concat()

    // Body: Apple icon grid, 824 of 1024.
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = squircle(body)
    shadow(0.30, blur: 30, dy: -14) { rgb(0x000000).setFill(); shape.fill() }
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGradient(colors: [rgb(0x4A4A4F), rgb(0x1E1E21), rgb(0x050506)])!.draw(in: body, angle: -70)
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.30), NSColor.white.withAlphaComponent(0)])!
        .draw(fromCenter: NSPoint(x: 300, y: 900), radius: 0, toCenter: NSPoint(x: 300, y: 900), radius: 640, options: [])
    NSGraphicsContext.restoreGraphicsState()
    rim(squircle(body.insetBy(dx: 3, dy: 3)), width: 6, in: body, top: 0.7, bottom: 0.05)

    // Heartbeat line.
    let y: CGFloat = 512
    let pulse = NSBezierPath()
    pulse.move(to: NSPoint(x: 290, y: y))
    for p in [(420, y), (468, y + 170), (556, y - 190), (606, y), (734, y)] as [(CGFloat, CGFloat)] {
        pulse.line(to: NSPoint(x: p.0, y: p.1))
    }
    pulse.lineWidth = 64; pulse.lineJoinStyle = .round; pulse.lineCapStyle = .round
    shadow(0.28, blur: 22, dy: -12) { NSColor.white.setStroke(); pulse.stroke() }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

guard CommandLine.arguments.count > 1 else { print("usage: make-icon.swift <out.iconset>"); exit(1) }
let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for (name, px) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
                   ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
                   ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
    let data = render(pixels: px).representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
}
