import AppKit
import VitalCore

/// The menu bar glyph: a rounded tile with a heartbeat line cut out of it. Bold enough to read at 16-18 px.
/// Load is shown twice, so it never relies on colour alone: the heartbeat spike grows with the band, and
/// busy / struggling are drawn in orange / red. Calm is a template image (follows light and dark menu bars).
/// Busy and struggling are drawn coloured and non-template, because contentTintColor hides template status items.
enum PulseIcon {
    static let size: CGFloat = 18

    static func image(for band: LoadBand) -> NSImage {
        let ink: NSColor = band == .calm ? .black : (band == .busy ? .systemOrange : .systemRed)
        let amplitude: CGFloat = band == .calm ? 3.4 : (band == .busy ? 4.4 : 5.4)
        let draw: () -> Void = {
            let tile = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 1.5, width: 15, height: 15), xRadius: 4.6, yRadius: 4.6)
            ink.setFill()
            tile.fill()
            let mid: CGFloat = 9
            let line = NSBezierPath()
            line.move(to: NSPoint(x: 3, y: mid))
            line.line(to: NSPoint(x: 6.2, y: mid))
            line.line(to: NSPoint(x: 7.6, y: mid + amplitude))
            line.line(to: NSPoint(x: 9.6, y: mid - amplitude))
            line.line(to: NSPoint(x: 11.2, y: mid))
            line.line(to: NSPoint(x: 15, y: mid))
            line.lineWidth = 2
            line.lineJoinStyle = .round
            line.lineCapStyle = .round
            // Punch the line out of the tile so the menu bar shows through.
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            NSColor.black.setStroke()
            line.stroke()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
        }
        // Pre-render to bitmaps (1x and 2x) so the menu bar never has to run drawing code.
        let image = NSImage(size: NSSize(width: size, height: size))
        for scale in [1, 2] {
            let px = Int(size) * scale
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { continue }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            let t = NSAffineTransform(); t.scale(by: CGFloat(scale)); t.concat()
            draw()
            NSGraphicsContext.restoreGraphicsState()
            // Set the point size only after drawing: a context made from a rep whose size is already set
            // maps points to pixels itself, and the explicit scale above would then apply twice.
            rep.size = NSSize(width: size, height: size)
            image.addRepresentation(rep)
        }
        image.isTemplate = band == .calm
        return image
    }
}
