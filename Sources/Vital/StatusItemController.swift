import AppKit
import VitalCore

@MainActor
final class StatusItemController: NSObject {
    private let appState: AppState
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let panel: PanelController

    init(appState: AppState) {
        self.appState = appState
        panel = PanelController(appState: appState)
        super.init()
        guard let button = item.button else { return }
        // Pointing at the icon is the earliest sign the panel is about to open: take the first process
        // reading now so the app list has its numbers the moment the panel appears.
        button.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                              owner: self, userInfo: nil))
        apply(band: .calm)
        button.target = self
        button.action = #selector(clicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.setAccessibilityLabel("Vital")
        appState.onBandChange = { [weak self] band in self?.apply(band: band) }
    }

    func openPanel() {
        if let button = item.button, !panel.isVisible { panel.open(relativeTo: button) }
    }

    func closePanel() { panel.close() }

    private func apply(band: LoadBand) {
        item.button?.image = PulseIcon.image(for: band)
        let label: String
        switch band { case .calm: label = "Vital"; case .busy: label = "Vital, busy"; case .struggling: label = "Vital, Mac is struggling" }
        item.button?.setAccessibilityLabel(label)
    }

    @objc func mouseEntered(with event: NSEvent) {
        if !panel.isVisible { appState.sampler.prime() }
    }

    @objc private func showAbout() { AboutPanel.show() }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            panel.toggle(relativeTo: sender)
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "About Vital", action: #selector(showAbout), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Vital", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }
}
