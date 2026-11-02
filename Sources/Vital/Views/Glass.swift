import SwiftUI
import VitalCore

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

/// An inset card on top of the panel glass. Plain translucent fill, no border: glass on glass looks muddy.
struct CardStyle: ViewModifier {
    var radius: CGFloat = 14
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color.primary.opacity(0.055)))
    }
}

/// Three sizes only: large for the headline and tile numbers, medium for rows, small for labels.
enum Typo {
    static let large = Font.system(size: 20, weight: .semibold)
    static let number = Font.system(size: 20, weight: .semibold, design: .rounded)
    static let medium = Font.system(size: 13)
    static let mediumBold = Font.system(size: 13, weight: .medium)
    static let small = Font.system(size: 11)
    static let smallBold = Font.system(size: 11, weight: .semibold)
}

/// Soft highlight under the pointer, so rows read as tappable.
struct HoverRow: ViewModifier {
    @State private var hovering = false
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.06 : 0)).padding(.horizontal, -6))
            .onHover { hovering = $0 }
    }
}

extension View {
    func hoverRow() -> some View { modifier(HoverRow()) }
    func panelBackground() -> some View { modifier(PanelBackground()) }
    func card(radius: CGFloat = 14) -> some View { modifier(CardStyle(radius: radius)) }
}

enum Palette {
    static let green = Color(red: 0.19, green: 0.82, blue: 0.35)
    static let yellow = Color(red: 1.0, green: 0.80, blue: 0.04)
    static let orange = Color(red: 1.0, green: 0.62, blue: 0.04)
    static let red = Color(red: 1.0, green: 0.27, blue: 0.23)
    static let blue = Color(red: 0.36, green: 0.65, blue: 1.0)
    /// Chevrons and other quiet glyphs.
    static let faint = Color.primary.opacity(0.3)

    /// Status colour for a health level (icons, meters).
    static func color(_ l: HealthLevel) -> Color {
        switch l { case .good: return green; case .warning: return yellow; case .critical: return red }
    }
    /// Text in a warning colour: yellow is unreadable on a light background, so warnings use orange.
    static func text(_ l: HealthLevel) -> Color {
        switch l { case .good: return .primary; case .warning: return orange; case .critical: return red }
    }
}
