import AppKit

@MainActor
final class StatusItemController {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let panel = PanelController()

    init() {
        guard let button = item.button else { return }
        let image = NSImage(systemSymbolName: "testtube.2", accessibilityDescription: "Vital")
        image?.isTemplate = true
        button.image = image
        button.target = self
        button.action = #selector(clicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.setAccessibilityLabel("Vital")
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
