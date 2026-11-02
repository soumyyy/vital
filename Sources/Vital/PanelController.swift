import AppKit
import SwiftUI
import Darwin
import VitalCore

final class GlassPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

@MainActor
final class PanelController {
    private let appState: AppState
    private var panel: GlassPanel?
    private var model: PanelModel?
    private var clickMonitor: Any?
    static let size = NSSize(width: 340, height: 680)       // width, and the tallest the panel gets

    init(appState: AppState) { self.appState = appState }

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle(relativeTo button: NSStatusBarButton) {
        isVisible ? close() : open(relativeTo: button)
    }

    func open(relativeTo button: NSStatusBarButton) {
        let model = PanelModel(appState: appState)
        if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--tab=") }),
           let tab = PanelTab(argument: String(arg.dropFirst(6))) { model.tab = tab }   // for screenshots
        self.model = model
        let visible = (button.window?.screen ?? NSScreen.main)?.visibleFrame.height ?? Self.size.height
        model.maxHeight = min(Self.size.height, visible - 16)
        let panel = makePanel(model: model)
        self.panel = panel
        position(panel, below: button, height: model.maxHeight)
        model.onHeight = { [weak self] h in self?.resize(to: h) }
        panel.contentView?.layoutSubtreeIfNeeded()      // reports the content height, so the panel opens at its size
        panel.makeKeyAndOrderFront(nil)
        appState.sampler.setMode(.open)
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: panel, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
    }

    func close() {
        guard panel != nil else { return }
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
        appState.sampler.setMode(.closed)
        model?.close()
        model = nil
        panel?.orderOut(nil)
        panel?.contentView = nil          // release the whole SwiftUI tree while closed
        panel = nil
        // Hand freed heap pages back to the system so the closed footprint returns to its baseline.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { _ = malloc_zone_pressure_relief(nil, 0) }
    }

    /// Content height changed (a row expanded, another tile selected): keep the top edge under the menu bar icon.
    private func resize(to height: CGFloat) {
        guard let panel, let model else { return }
        let h = min(max(height.rounded(.up), 120), model.maxHeight)
        var f = panel.frame
        guard abs(f.height - h) >= 1 else { return }
        f.origin.y += f.height - h
        f.size.height = h
        panel.setFrame(f, display: true)
        panel.invalidateShadow()
    }

    private func makePanel(model: PanelModel) -> GlassPanel {
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

        let hosting = NSHostingView(rootView: PanelView(model: model))
        hosting.sizingOptions = []          // the controller sizes the window from the reported content height
        hosting.frame = NSRect(origin: .zero, size: Self.size)
        hosting.autoresizingMask = [.width, .height]
        if #available(macOS 26, *) {
            p.contentView = hosting
        } else {
            let blur = GlassBackground(frame: NSRect(origin: .zero, size: Self.size))
            blur.addSubview(hosting)
            p.contentView = blur
        }
        return p
    }

    private func position(_ panel: NSPanel, below button: NSStatusBarButton, height: CGFloat) {
        guard let window = button.window else { return }
        let buttonFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        var x = buttonFrame.midX - Self.size.width / 2
        x = min(max(x, visible.minX + 8), visible.maxX - Self.size.width - 8)
        let y = max(visible.minY + 8, buttonFrame.minY - height - 6)
        panel.setFrame(NSRect(x: x, y: y, width: Self.size.width, height: height), display: true)
    }
}

/// Frosted background used below macOS 26.
final class GlassBackground: NSVisualEffectView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 26
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
    }
    required init?(coder: NSCoder) { fatalError() }
}
