import SwiftUI
import VitalCore

/// Line chart drawn with plain shapes. A SwiftUI `Canvas` here cost about 60 MB of GPU memory while the
/// panel was open (measured), so this deliberately avoids Canvas and drawingGroup.
struct Sparkline: View {
    let values: [Double]
    var color: Color = Palette.blue

    var body: some View {
        GeometryReader { geo in
            let line = linePath(in: geo.size)
            ZStack {
                fillPath(line, in: geo.size)
                    .fill(LinearGradient(colors: [color.opacity(0.35), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                line.stroke(color, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            }
        }
        .accessibilityHidden(true)
    }

    private func linePath(in size: CGSize) -> Path {
        var p = Path()
        guard values.count > 1 else { return p }
        let step = size.width / CGFloat(values.count - 1)
        for (i, v) in values.enumerated() {
            let pt = CGPoint(x: CGFloat(i) * step, y: size.height - CGFloat(min(max(v, 0), 1)) * (size.height - 2) - 1)
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        return p
    }

    private func fillPath(_ line: Path, in size: CGSize) -> Path {
        var p = line
        guard values.count > 1 else { return p }
        p.addLine(to: CGPoint(x: size.width, y: size.height))
        p.addLine(to: CGPoint(x: 0, y: size.height))
        p.closeSubpath()
        return p
    }
}

/// Thin meter under a tile number. Neutral when the vital is fine; yellow or red only when it matters.
struct Meter: View {
    let fraction: Double?
    let level: HealthLevel
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                if let f = fraction {
                    Capsule().fill(level == .good ? AnyShapeStyle(Color.primary.opacity(0.4)) : AnyShapeStyle(Palette.color(level)))
                        .frame(width: max(3, geo.size.width * CGFloat(min(max(f, 0), 1))))
                }
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}
