import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appState: AppState?
    private var statusController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let state = AppState()
        appState = state
        statusController = StatusItemController(appState: state)
        state.start()
        if CommandLine.arguments.contains("--open-panel") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.statusController?.openPanel() }
        }
    }
}
