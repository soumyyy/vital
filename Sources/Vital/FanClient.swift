import AppKit
import ServiceManagement
import VitalCore
import VitalFanIPC

/// Owns one authenticated helper connection for the app lifetime, including while the panel is closed.
@MainActor
final class FanClient: ObservableObject {
    @Published private(set) var targets: [Int: Double] = [:]
    @Published private(set) var error: String?
    @Published private(set) var busy = false
    @Published private(set) var connecting = false
    @Published private(set) var connected = false

    private let service = SMAppService.daemon(plistName: FanService.plist)
    private var connection: NSXPCConnection?
    private var connectionID: UUID?
    private var heartbeat: Timer?
    private var statusPending = false
    private var statusError: String?
    private var statusTimeout: Task<Void, Never>?
    private var requestID: UUID?
    private var requestTimeout: Task<Void, Never>?

    var availability: FanControlAvailability {
        guard !connected else { return .available }
        let reason: String
        switch service.status {
        case .enabled:
            reason = connecting ? "Connecting to fan control…" : "Reconnect to adjust fan speed."
        case .requiresApproval:
            reason = "Approve Vital in System Settings → General → Login Items & Extensions."
        default:
            reason = "Enable fan control to adjust speed. macOS will ask for approval."
        }
        return .unavailable(reason: reason)
    }

    // MARK: updating Vital

    private static let reenableKey = "vital.fan.reenableAfterUpdate"

    /// The helper is registered against this bundle's signature. Remove it before the bundle is replaced and
    /// remember to register it again from the new version.
    static func prepareForUpdate() async {
        let service = SMAppService.daemon(plistName: FanService.plist)
        guard service.status == .enabled || service.status == .requiresApproval else { return }
        try? await service.unregister()
        UserDefaults.standard.set(true, forKey: reenableKey)
    }

    /// First launch after an update: put the helper back so fan control keeps working.
    static func completeUpdate() {
        guard UserDefaults.standard.bool(forKey: reenableKey) else { return }
        UserDefaults.standard.removeObject(forKey: reenableKey)
        let service = SMAppService.daemon(plistName: FanService.plist)
        try? service.register()
    }

    var needsApproval: Bool { service.status == .requiresApproval }

    var setupTitle: String {
        switch service.status {
        case .enabled: return "Reconnect"
        case .requiresApproval: return "Approve control"
        default: return "Enable control"
        }
    }

    func enable() {
        error = nil
        // First-time bundled daemons can report notFound before registration.
        if service.status == .notRegistered || service.status == .notFound {
            do { try service.register() }
            catch { self.error = "Could not enable fan control. \(error.localizedDescription)" }
        }
        // register() can throw EPERM while successfully entering requiresApproval.
        switch service.status {
        case .requiresApproval:
            error = nil
            SMAppService.openSystemSettingsLoginItems()
        case .enabled:
            error = nil
            refresh()
        case .notFound, .notRegistered:
            if error == nil { error = "Could not enable fan control. Reinstall Vital and try again." }
        @unknown default:
            error = "macOS returned an unknown fan control status."
        }
        objectWillChange.send()
    }

    private func remote() -> FanServiceProtocol? {
        if connection == nil {
            guard service.status == .enabled else { return nil }
            guard let executable = Bundle.main.executableURL,
                  let requirement = FanService.requirement(for: executable.deletingLastPathComponent().appendingPathComponent("VitalFanHelper")) else {
                error = "The fan helper signature is invalid. Reinstall Vital and try again."
                return nil
            }
            let id = UUID()
            let connection = NSXPCConnection(machServiceName: FanService.name, options: .privileged)
            connection.setCodeSigningRequirement(requirement)
            connection.remoteObjectInterface = NSXPCInterface(with: FanServiceProtocol.self)
            connection.invalidationHandler = { [weak self] in
                Task { @MainActor in self?.disconnect(id: id, message: "Fan control disconnected. Reconnect to try again.") }
            }
            connection.interruptionHandler = { [weak connection] in connection?.invalidate() }
            self.connection = connection
            connectionID = id
            connecting = true
            connection.resume()
        }
        let id = connectionID
        return connection?.remoteObjectProxyWithErrorHandler { [weak self] _ in
            Task { @MainActor in
                guard let id else { return }
                self?.disconnect(id: id, message: "Could not reach fan control. Reconnect to try again.")
            }
        } as? FanServiceProtocol
    }

    /// Polling also renews the helper's manual-control lease. Only one status request may be in flight.
    func refresh() {
        guard !statusPending, let remote = remote(), let id = connectionID else { return }
        statusPending = true
        statusTimeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            self?.disconnect(id: id, message: "Fan control did not respond. Reconnect to try again.")
        }
        remote.status { [weak self] values, message in
            Task { @MainActor in
                guard let self, self.connectionID == id else { return }
                self.statusTimeout?.cancel()
                self.statusTimeout = nil
                self.statusPending = false
                let wasConnected = self.connected
                self.connected = true
                self.connecting = false
                self.targets = Dictionary(uniqueKeysWithValues: values.compactMap { key, value in
                    guard let index = Int(key), (0..<8).contains(index), value.doubleValue.isFinite else { return nil }
                    return (index, value.doubleValue)
                })
                if let message { self.error = message }
                else if !wasConnected || self.error == self.statusError { self.error = nil }
                self.statusError = message
                // The helper only needs its lease renewed while a manual speed is set. Otherwise stay quiet.
                if self.targets.isEmpty {
                    self.heartbeat?.invalidate(); self.heartbeat = nil
                } else if self.heartbeat == nil {
                    self.heartbeat = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                        Task { @MainActor in self?.refresh() }
                    }
                }
            }
        }
    }

    /// The panel closed. With no manual speed to keep alive there is nothing to hold the connection for.
    func panelClosed() { if targets.isEmpty && !busy { stop() } }

    var isManual: Bool { !targets.isEmpty }

    /// Switches every fan between a manual speed (starting from where it is, never below its minimum) and Auto.
    func setManual(_ on: Bool, fans: [FanReading]) {
        Task { @MainActor [weak self] in
            for fan in fans {
                guard let self else { return }
                while self.busy { try? await Task.sleep(for: .milliseconds(50)) }
                guard self.connected else { return }
                if on {
                    guard let lo = fan.minRPM, lo > 0 else { continue }
                    self.set(fan: fan.index, rpm: max(lo, fan.rpm))
                } else if self.targets[fan.index] != nil {
                    self.set(fan: fan.index, rpm: -1)
                }
                try? await Task.sleep(for: .milliseconds(300))      // the helper limits how fast a fan can be changed
            }
        }
    }

    func set(fan: Int, rpm: Double) {
        guard !busy, connected, let remote = remote() else { return }
        busy = true
        error = nil
        let request = UUID()
        requestID = request
        requestTimeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            guard let self, self.requestID == request, let id = self.connectionID else { return }
            self.disconnect(id: id, message: "Fan change timed out. Reconnect to check its status.")
        }
        remote.set(fan: fan, rpm: rpm) { [weak self] message in
            Task { @MainActor in
                guard let self, self.requestID == request else { return }
                self.requestTimeout?.cancel()
                self.requestTimeout = nil
                self.requestID = nil
                self.busy = false
                self.error = message
                self.refresh()
            }
        }
    }

    private func disconnect(id: UUID, message: String) {
        guard connectionID == id else { return }
        stop()
        error = message
    }

    func stop() {
        // Clear identity before invalidating: callbacks from an old connection must not erase a new one.
        connectionID = nil
        let oldConnection = connection
        connection = nil
        heartbeat?.invalidate()
        heartbeat = nil
        statusTimeout?.cancel()
        statusTimeout = nil
        requestTimeout?.cancel()
        requestTimeout = nil
        requestID = nil
        statusPending = false
        statusError = nil
        connecting = false
        connected = false
        busy = false
        targets = [:]
        oldConnection?.invalidate()
    }
}
