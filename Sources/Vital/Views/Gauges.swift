import SwiftUI
import VitalCore

struct Sparkline: View {
    let values: [Double]
    var color: Color = Palette.blue

    var body: some View {
        Canvas { ctx, size in
            guard values.count > 1 else { return }
            let step = size.width / CGFloat(max(values.count - 1, 1))
            var line = Path()
            for (i, v) in values.enumerated() {
                let p = CGPoint(x: CGFloat(i) * step, y: size.height - CGFloat(min(max(v, 0), 1)) * (size.height - 2) - 1)
                i == 0 ? line.move(to: p) : line.addLine(to: p)
            }
            var fill = line
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.addLine(to: CGPoint(x: 0, y: size.height))
            fill.closeSubpath()
            ctx.fill(fill, with: .linearGradient(Gradient(colors: [color.opacity(0.35), color.opacity(0.02)]),
                                                 startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            ctx.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
        }
        .accessibilityHidden(true)
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
