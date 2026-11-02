import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appState: AppState?
    private var statusController: StatusItemController?

    func applicationWillTerminate(_ notification: Notification) { appState?.fanController.stop() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let state = AppState()
        appState = state
        statusController = StatusItemController(appState: state)
        state.start()
        if CommandLine.arguments.contains("--open-panel") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.statusController?.openPanel() }
            // Debug aid for measuring memory after the panel closes: --close-panel-after=<seconds>
            if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--close-panel-after=") }),
               let secs = Double(arg.dropFirst("--close-panel-after=".count)) {
                DispatchQueue.main.asyncAfter(deadline: .now() + secs) { [weak self] in self?.statusController?.closePanel() }
            }
        }
    }
}
