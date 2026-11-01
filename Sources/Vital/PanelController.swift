import AppKit

final class GlassPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

@MainActor
final class PanelController {
    private var panel: GlassPanel?
    private var clickMonitor: Any?
    static let size = NSSize(width: 340, height: 560)

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle(relativeTo button: NSStatusBarButton) {
        isVisible ? close() : open(relativeTo: button)
    }

    func open(relativeTo button: NSStatusBarButton) {
        let panel = makePanel()
        self.panel = panel
        position(panel, below: button)
        panel.makeKeyAndOrderFront(nil)
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
    }

    func close() {
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
        panel?.orderOut(nil)
        panel?.contentView = nil   // release the view tree while closed
        panel = nil
    }

    private func makePanel() -> GlassPanel {
        let p = GlassPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .popUpMenu
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.isReleasedWhenClosed = false
        p.contentView = GlassBackground(frame: NSRect(origin: .zero, size: Self.size))
        return p
    }

    private func position(_ panel: NSPanel, below button: NSStatusBarButton) {
        guard let window = button.window else { return }
        let buttonFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = window.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        var x = buttonFrame.midX - Self.size.width / 2
        x = min(max(x, visible.minX + 8), visible.maxX - Self.size.width - 8)
        let y = buttonFrame.minY - Self.size.height - 6
        panel.setFrame(NSRect(x: x, y: y, width: Self.size.width, height: Self.size.height), display: true)
    }
}

/// Frosted background used below macOS 26 and as the base layer everywhere.
final class GlassBackground: NSVisualEffectView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 22
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
    }
    required init?(coder: NSCoder) { fatalError() }
}
