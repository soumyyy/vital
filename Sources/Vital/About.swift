import AppKit

/// The standard About window with one line about what Vital is.
enum AboutPanel {
    @MainActor static func show() {
        let credits = NSMutableAttributedString(
            string: "Vital is an open-source tool, made to make your life easier.\n\nMIT licensed.",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor,
                         .paragraphStyle: { let p = NSMutableParagraphStyle(); p.alignment = .center; return p }()])
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}
