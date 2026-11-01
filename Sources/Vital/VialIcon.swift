import AppKit
import VitalCore

/// The vial glyph for the menu bar. Drawn as a template image; liquid level and tint follow the load band.
enum VialIcon {
    static func image(for band: LoadBand) -> NSImage {
        let level: CGFloat = band == .calm ? 3.9 : (band == .busy ? 6.4 : 8.9)
        let draw: () -> Void = {
            let flask = NSBezierPath()
            flask.move(to: NSPoint(x: 7, y: 16))
            flask.line(to: NSPoint(x: 7, y: 10.5))
            flask.line(to: NSPoint(x: 3.3, y: 3.9))
            flask.curve(to: NSPoint(x: 5.2, y: 1.5), controlPoint1: NSPoint(x: 2.4, y: 2.2), controlPoint2: NSPoint(x: 3.6, y: 1.5))
            flask.line(to: NSPoint(x: 12.8, y: 1.5))
            flask.curve(to: NSPoint(x: 14.7, y: 3.9), controlPoint1: NSPoint(x: 14.4, y: 1.5), controlPoint2: NSPoint(x: 15.6, y: 2.2))
            flask.line(to: NSPoint(x: 11, y: 10.5))
            flask.line(to: NSPoint(x: 11, y: 16))
            NSColor.black.setStroke()
            flask.lineWidth = 1.4
            flask.lineJoinStyle = .round
            flask.lineCapStyle = .round
            flask.stroke()

            let rim = NSBezierPath()
            rim.move(to: NSPoint(x: 5.8, y: 16.4)); rim.line(to: NSPoint(x: 12.2, y: 16.4))
            rim.lineWidth = 1.4; rim.lineCapStyle = .round
            rim.stroke()

            NSGraphicsContext.saveGraphicsState()
            let clip = flask.copy() as! NSBezierPath
            clip.close()
            clip.addClip()
            NSColor.black.setFill()
            NSRect(x: 0, y: 0, width: 18, height: level).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        // Pre-render to a bitmap (1x and 2x) so the menu bar never has to run drawing code.
        let image = NSImage(size: NSSize(width: 18, height: 18))
        for scale in [1, 2] {
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 18 * scale, pixelsHigh: 18 * scale,
                                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { continue }
            rep.size = NSSize(width: 18, height: 18)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            let t = NSAffineTransform(); t.scaleX(by: CGFloat(scale), yBy: CGFloat(scale)); t.concat()
            draw()
            NSGraphicsContext.restoreGraphicsState()
            image.addRepresentation(rep)
        }
        image.isTemplate = true
        return image
    }

    static func tint(for band: LoadBand) -> NSColor? {
        switch band {
        case .calm: return nil
        case .busy: return .systemOrange
        case .struggling: return .systemRed
        }
    }
}
