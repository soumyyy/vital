// Renders Vital's app icon (the vial on a glass-rimmed gradient squircle) into an .iconset folder.
// Usage: swift Scripts/make-icon.swift build/AppIcon.iconset && iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
import AppKit

func flask() -> NSBezierPath {
    let p = NSBezierPath()
    p.move(to: NSPoint(x: 7, y: 16))
    p.line(to: NSPoint(x: 7, y: 10.5))
    p.line(to: NSPoint(x: 3.3, y: 3.9))
    p.curve(to: NSPoint(x: 5.2, y: 1.5), controlPoint1: NSPoint(x: 2.4, y: 2.2), controlPoint2: NSPoint(x: 3.6, y: 1.5))
    p.line(to: NSPoint(x: 12.8, y: 1.5))
    p.curve(to: NSPoint(x: 14.7, y: 3.9), controlPoint1: NSPoint(x: 14.4, y: 1.5), controlPoint2: NSPoint(x: 15.6, y: 2.2))
    p.line(to: NSPoint(x: 11, y: 10.5))
    p.line(to: NSPoint(x: 11, y: 16))
    return p
}

func render(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(pixels) / 1024
    let t = NSAffineTransform(); t.scaleX(by: s, yBy: s); t.concat()

    // Squircle body (Apple icon grid: 824 of 1024, ~22.4% corner radius)
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = NSBezierPath(roundedRect: body, xRadius: 184, yRadius: 184)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 28; shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    NSColor(red: 0.30, green: 0.40, blue: 1.0, alpha: 1).setFill()
    squircle.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()
    NSGradient(colors: [NSColor(red: 0.36, green: 0.66, blue: 1.0, alpha: 1), NSColor(red: 0.47, green: 0.24, blue: 1.0, alpha: 1)])!
        .draw(in: body, angle: -60)
    // soft top-left glow
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.35), NSColor.white.withAlphaComponent(0)])!
        .draw(fromCenter: NSPoint(x: 330, y: 820), radius: 0, toCenter: NSPoint(x: 330, y: 820), radius: 520, options: [])
    NSGraphicsContext.restoreGraphicsState()

    // glass rim
    NSColor.white.withAlphaComponent(0.45).setStroke()
    let rim = NSBezierPath(roundedRect: body.insetBy(dx: 1.5, dy: 1.5), xRadius: 183, yRadius: 183)
    rim.lineWidth = 3; rim.stroke()

    // vial: glyph coordinates are 0...18, mapped to ~560 px tall, centred
    let scale: CGFloat = 36
    let place = NSAffineTransform()
    place.translateX(by: 512 - 9 * scale, yBy: 512 - 9 * scale + 10)
    place.scale(by: scale)
    let glass = flask(); glass.transform(using: place as AffineTransform)

    NSColor.white.withAlphaComponent(0.20).setFill()
    let closed = glass.copy() as! NSBezierPath; closed.close(); closed.fill()

    NSGraphicsContext.saveGraphicsState()
    closed.addClip()
    let liquidTop = (512 - 9 * scale + 10) + 7.2 * scale
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.98), NSColor.white.withAlphaComponent(0.78)])!
        .draw(in: NSRect(x: 0, y: 0, width: 1024, height: liquidTop), angle: 90)
    NSGraphicsContext.restoreGraphicsState()

    NSColor.white.setStroke()
    glass.lineWidth = 1.5 * scale * 0.95; glass.lineJoinStyle = .round; glass.lineCapStyle = .round
    glass.stroke()
    let lip = NSBezierPath()
    lip.move(to: NSPoint(x: 5.8, y: 16.4)); lip.line(to: NSPoint(x: 12.2, y: 16.4))
    lip.transform(using: place as AffineTransform)
    lip.lineWidth = 1.5 * scale * 0.95; lip.lineCapStyle = .round
    lip.stroke()

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
