import AppKit
import ServiceManagement
import VitalCore
import VitalFanIPC

@MainActor
final class FanClient: ObservableObject {
    @Published private(set) var targets: [Int: Double] = [:]
    @Published private(set) var error: String?
    @Published private(set) var busy = false
    private var connection: NSXPCConnection?
    private var timer: Timer?
    private var pending: [UUID: (String?) -> Void] = [:]
    private let service = SMAppService.daemon(plistName: FanService.plist)
    var availability: FanControlAvailability {
        service.status == .enabled ? .available : .unavailable(reason: "Enable fan control and approve Vital in System Settings.")
    }

    func enable() {
        do {
            if service.status == .notRegistered { try service.register() }
            if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            error = nil
        } catch { self.error = error.localizedDescription }
        objectWillChange.send()
        refresh()
    }
    private func remote() -> FanServiceProtocol? {
        if connection == nil {
            guard service.status == .enabled,
                  let executable = Bundle.main.executableURL,
                  let requirement = FanService.requirement(for: executable.deletingLastPathComponent().appendingPathComponent("VitalFanHelper")) else { return nil }
            let c = NSXPCConnection(machServiceName: FanService.name, options: .privileged)
            c.setCodeSigningRequirement(requirement)
            c.remoteObjectInterface = NSXPCInterface(with: FanServiceProtocol.self)
            c.invalidationHandler = { [weak self] in Task { @MainActor in
                self?.connection = nil; self?.targets = [:]
                self?.error = "Fan helper disconnected. Check fan status before continuing."
                self?.failPending("Fan helper disconnected. Check fan status before continuing.")
            } }
            c.interruptionHandler = { [weak c] in c?.invalidate() }
            connection = c
            c.resume()
            timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        }
        return connection?.remoteObjectProxyWithErrorHandler { [weak self] error in
            Task { @MainActor in self?.error = error.localizedDescription; self?.connection?.invalidate() }
        } as? FanServiceProtocol
    }
    func refresh() {
        guard let remote = remote() else { return }
        remote.status { [weak self] values, message in Task { @MainActor in
            self?.targets = Dictionary(uniqueKeysWithValues: values.compactMap { key, value in Int(key).map { ($0, value.doubleValue) } })
            if let message { self?.error = message }
        } }
    }
    func set(fan: Int, rpm: Double) {
        guard !busy else { return }
        guard let remote = remote() else { error = "Enable and approve the fan helper first."; return }
        busy = true; error = nil
        let id = UUID()
        pending[id] = { [weak self] message in
            self?.busy = false; self?.error = message; self?.refresh()
        }
        remote.set(fan: fan, rpm: rpm) { [weak self] message in
            Task { @MainActor in self?.pending.removeValue(forKey: id)?(message) }
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self, let finish = self.pending.removeValue(forKey: id) else { return }
            self.connection?.invalidate()
            finish("Fan helper did not respond. Check fan status before continuing.")
        }
    }
    private func failPending(_ message: String) {
        timer?.invalidate(); timer = nil
        let callbacks = Array(pending.values); pending.removeAll()
        for callback in callbacks { callback(message) }
    }
    func stop() { timer?.invalidate(); timer = nil; connection?.invalidate(); connection = nil }
}
