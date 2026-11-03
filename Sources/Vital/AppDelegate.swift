import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appState: AppState?
    private var statusController: StatusItemController?

    func applicationWillTerminate(_ notification: Notification) {
        appState?.saveHistory()
        appState?.fanController.stop()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installApplicationMenu()
        let state = AppState()
        state.fanController.resumeAfterUpdate()
        state.fanController.repairHelperIfStale()
        appState = state
        statusController = StatusItemController(appState: state)
        state.start()
        if CommandLine.arguments.contains("--show-about") {      // for screenshots
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { AboutPanel.show(checkNow: CommandLine.arguments.contains("--check")) }
        }
        if CommandLine.arguments.contains("--open-panel") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.statusController?.openPanel() }
            // Debug aid for measuring memory after the panel closes: --close-panel-after=<seconds>
            if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--close-panel-after=") }),
               let secs = Double(arg.dropFirst("--close-panel-after=".count)) {
                DispatchQueue.main.asyncAfter(deadline: .now() + secs) { [weak self] in self?.statusController?.closePanel() }
            }
        }
    }
    // Finder, Spotlight and `open -a Vital` send a reopen event to an already running app.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusController?.openPanel()
        return false
    }

    private func installApplicationMenu() {
        let main = NSMenu()
        let app = NSMenu(title: "Vital")
        let item = NSMenuItem()
        item.submenu = app
        main.addItem(item)
        app.addItem(withTitle: "About Vital", action: #selector(showAbout), keyEquivalent: "").target = self
        app.addItem(withTitle: "Update Software…", action: #selector(updateSoftware), keyEquivalent: "").target = self
        app.addItem(.separator())
        app.addItem(withTitle: "Quit Vital", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q").target = NSApp
        NSApp.mainMenu = main
    }

    @objc private func showAbout() { AboutPanel.show() }
    @objc private func updateSoftware() { AboutPanel.show(checkNow: true) }

}
