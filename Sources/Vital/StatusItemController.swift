import AppKit
import VitalCore

@MainActor
final class StatusItemController {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let panel: PanelController

    init(appState: AppState) {
        panel = PanelController(appState: appState)
        guard let button = item.button else { return }
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

    private func apply(band: LoadBand) {
        item.button?.image = VialIcon.image(for: band)
        let label: String
        switch band { case .calm: label = "Vital"; case .busy: label = "Vital, busy"; case .struggling: label = "Vital, Mac is struggling" }
        item.button?.setAccessibilityLabel(label)
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            panel.toggle(relativeTo: sender)
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "About Vital", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Vital", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }
}
