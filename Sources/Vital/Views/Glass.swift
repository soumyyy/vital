import SwiftUI

/// Panel-level background: Liquid Glass on macOS 26+, frosted material below, opaque with Reduce Transparency.
struct PanelBackground: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    static let radius: CGFloat = 26

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        if reduceTransparency {
            content.background(shape.fill(Color(nsColor: .windowBackgroundColor)))
                .overlay(shape.strokeBorder(.primary.opacity(0.15)))
        } else if #available(macOS 26, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            // Below macOS 26 the frosted blur comes from an NSVisualEffectView behind this view.
            content.overlay(shape.strokeBorder(.white.opacity(0.18)))
        }
    }
}

/// An inset card on top of the panel glass. Plain translucent fill: glass on glass looks muddy.
struct CardStyle: ViewModifier {
    var radius: CGFloat = 14
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.primary.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(.primary.opacity(0.08)))
    }
}

extension View {
    func panelBackground() -> some View { modifier(PanelBackground()) }
    func card(radius: CGFloat = 14) -> some View { modifier(CardStyle(radius: radius)) }
}

enum Palette {
    static let green = Color(red: 0.19, green: 0.82, blue: 0.35)
    static let yellow = Color(red: 1.0, green: 0.80, blue: 0.04)
    static let orange = Color(red: 1.0, green: 0.62, blue: 0.04)
    static let red = Color(red: 1.0, green: 0.27, blue: 0.23)
    static let blue = Color(red: 0.36, green: 0.65, blue: 1.0)

    /// Load level: green under 60%, yellow to 85%, red above.
    static func level(_ fraction: Double) -> Color { fraction < 0.6 ? green : (fraction < 0.85 ? yellow : red) }
}
