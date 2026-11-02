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

struct UsageBar: View {
    let fraction: Double
    let color: Color
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.12))
                Capsule().fill(color).frame(width: max(4, geo.size.width * CGFloat(min(max(fraction, 0), 1))))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

/// Green-yellow-red scale with a marker at the current temperature.
struct ThermalScale: View {
    let fraction: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(LinearGradient(colors: [Palette.green, Palette.yellow, Palette.red],
                                              startPoint: .leading, endPoint: .trailing))
                    .frame(height: 8).opacity(0.9)
                Capsule().fill(.white)
                    .frame(width: 4, height: 14)
                    .shadow(color: .black.opacity(0.4), radius: 2)
                    .offset(x: max(0, min(geo.size.width - 4, geo.size.width * CGFloat(fraction) - 2)))
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }
}
