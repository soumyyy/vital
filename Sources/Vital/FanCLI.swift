import AppKit
import ServiceManagement
import VitalCore
import VitalFanIPC

/// Explicit support commands. Normal app launch never changes fan speed.
enum FanCLI {
    static func runIfRequested(_ args: ArraySlice<String>) -> Bool {
        let service = SMAppService.daemon(plistName: FanService.plist)
        if args.contains("--unregister-fan-helper") || args.contains("--refresh-fan-helper") {
            let refresh = args.contains("--refresh-fan-helper")
            Task { @MainActor in
                do {
                    if service.status == .enabled || service.status == .requiresApproval { try await service.unregister() }
                    let legacy = SMAppService.daemon(plistName: FanService.legacyPlist)
                    if legacy.status == .enabled || legacy.status == .requiresApproval { try await legacy.unregister() }
                    guard refresh else { print("Fan helper unregistered."); exit(0) }
                    if let message = FanService.registrationError() { print(message); exit(1) }
                    try? await Task.sleep(for: .seconds(1))
                    do { try service.register() }
                    catch { print(error.localizedDescription) }
                    print("Helper status: \(service.status.rawValue)")
                    exit(service.status == .enabled ? 0 : 1)
                } catch { print(error.localizedDescription); exit(1) }
            }
            RunLoop.main.run()
            return true
        }
        if args.contains("--fan-helper-status") || args.contains("--register-fan-helper") {
            print("Bundle: \(Bundle.main.bundleURL.path)")
            print("Helper status: \(service.status.rawValue)")
            let hardware = SMCFanHardware()
            for key in ["FNum", "F0Ac", "F0Mn", "F0Mx", "F0Md", "F0Tg"] {
                print("\(key): \(hardware.number(key).map(String.init(describing:)) ?? "unavailable")")
            }
            if args.contains("--register-fan-helper") {
                MainActor.assumeIsolated {
                    let controller = FanClient()
                    controller.enable()
                    if let error = controller.error { print(error) }
                    controller.stop()
                }
                print("Helper status after registration: \(service.status.rawValue)")
            }
            return true
        }
        if args.contains("--probe-fan-control") {
            let succeeded = MainActor.assumeIsolated { probe() }
            if !succeeded { exit(1) }
            return true
        }
        return false
    }

    /// Exercises the same controller as the slider, briefly at 4,000 rpm, then restores Auto.
    @MainActor
    private static func probe() -> Bool {
        let controller = FanClient()
        defer { controller.stop() }
        controller.refresh()
        guard wait(until: { controller.connected || controller.error != nil }, seconds: 6), controller.connected else {
            print(controller.error ?? "Fan helper did not connect."); return false
        }
        guard let fan = ThermalSampler.readFans().first,
              let target = FanSafety.target(requested: 4000, minRPM: fan.minRPM, maxRPM: fan.maxRPM) else {
            print("No controllable fan found."); return false
        }
        controller.set(fan: fan.index, rpm: target)
        guard wait(until: { !controller.busy }, seconds: 9), controller.error == nil else {
            print(controller.error ?? "Fan change timed out."); return false
        }
        let settled = Date().addingTimeInterval(5)
        while Date() < settled { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
        let hardware = SMCFanHardware()
        let actual = hardware.number("F\(fan.index)Ac") ?? -1
        let reachedTarget = abs(actual - target) <= max(250, target * 0.1)
        print("Requested \(target) rpm; actual \(actual) rpm.")
        controller.set(fan: fan.index, rpm: -1)
        _ = wait(until: { !controller.busy }, seconds: 9)
        let mode = hardware.number("F\(fan.index)Md")
        guard controller.error == nil && (mode == 0 || mode == 3) else {
            print(controller.error ?? "Could not verify Auto."); return false
        }
        print("Verified Auto restored.")
        if !reachedTarget { print("Fan did not reach the requested speed during the probe.") }
        return reachedTarget
    }

    @MainActor
    private static func wait(until condition: () -> Bool, seconds: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        return condition()
    }
}
