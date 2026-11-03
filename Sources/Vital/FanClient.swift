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

    private static var updateRecovery: HelperUpdateRecovery {
        HelperUpdateRecovery(service: FanUpdateService())
    }

    static func prepareForUpdate() async throws -> Bool {
        try await updateRecovery.prepare()
    }

    @discardableResult
    static func completeUpdate() -> String? {
        do {
            return try updateRecovery.restore()
                ? "macOS needs approval for fan control again. Select Approve control to open System Settings."
                : nil
        } catch {
            return "Fan control could not be restored after the update. Reconnect to try again."
        }
    }

    func resumeAfterUpdate() {
        if let message = Self.completeUpdate() { error = message }
    }

    // MARK: keeping the helper current

    private static let helperBuildKey = "vital.fan.helperBuild"
    /// Set once fan control has worked, so a registration lost to `brew upgrade` or a reinstall (Homebrew unregisters
    /// the helper on both) comes back at the next launch without a click. macOS keeps the approval across it.
    private static let wantedKey = "vital.fan.wanted"

    /// Restarts the helper when it is not the one bundled with this app. Copying a new Vital over the old one
    /// (a DMG drag, Homebrew, a restore) leaves the previous helper process running, and it refuses the new app.
    /// Unregistering and registering again starts the bundled helper; macOS keeps the existing approval.
    /// `force` does it even when the recorded build matches, for a helper that no longer answers.
    static func repairHelper(force: Bool = false) async {
        guard FanService.registrationError() == nil else { return }       // only the signed copy in /Applications
        let defaults = UserDefaults.standard
        let service = SMAppService.daemon(plistName: FanService.plist)
        guard let build = FanService.bundledHelperBuild() else { return }
        if service.status == .notRegistered, defaults.bool(forKey: wantedKey) {
            try? service.register()                                         // approved before, so this does not prompt
            if service.status == .enabled { defaults.set(build, forKey: helperBuildKey) }
            return
        }
        guard service.status == .enabled else { return }
        defaults.set(true, forKey: wantedKey)
        if !force, defaults.string(forKey: helperBuildKey) == build { return }
        do { try await service.unregister() } catch { return }
        try? await Task.sleep(for: .seconds(1))
        try? service.register()
        if service.status == .enabled { defaults.set(build, forKey: helperBuildKey) }
    }

    /// Runs at launch, before any connection is made.
    func repairHelperIfStale() {
        Task { [weak self] in
            await Self.repairHelper()
            self?.objectWillChange.send()
        }
    }

    private var unreachable = false

    var needsApproval: Bool { service.status == .requiresApproval }

    var setupTitle: String {
        switch service.status {
        case .enabled: return "Reconnect"
        case .requiresApproval: return "Approve control"
        default: return "Enable control"
        }
    }

    func enable() {
        if let message = FanService.registrationError() {
            error = message
            return
        }
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
            UserDefaults.standard.set(true, forKey: Self.wantedKey)
            if unreachable {
                // The helper is registered but not answering: restart it, then connect again.
                unreachable = false
                stop()
                Task { [weak self] in
                    await Self.repairHelper(force: true)
                    self?.refresh()
                }
            } else {
                if let build = FanService.bundledHelperBuild() { UserDefaults.standard.set(build, forKey: Self.helperBuildKey) }
                refresh()
            }
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
        unreachable = true
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

@MainActor
private final class FanUpdateService: UpdateHelperService {
    private let service = SMAppService.daemon(plistName: FanService.plist)
    var state: HelperRegistrationState {
        switch service.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered: return .unregistered
        default: return .unavailable
        }
    }
    func register() throws { try service.register() }
    func unregister() async throws { try await service.unregister() }
}
