import Foundation
import AppKit
import Darwin

public enum ActionOutcome: Equatable, Sendable {
    case gone          // every process in the target has exited
    case stillRunning  // graceful quit did not finish in time; offer Force Quit
    case stuck         // survived SIGKILL: blocked in the kernel (usually a disk or network volume)
    case denied        // we are not allowed to signal it (owned by root or another user)
    case protected     // Vital refuses to touch it
}

public protocol ProcessControl {
    /// Returns 0 or the errno from kill().
    func signal(_ pid: Int32, _ sig: Int32) -> Int32
    /// True if the exact process (pid plus start time) is still running and not a zombie.
    func isAlive(_ key: ProcessKey) -> Bool
    /// Asks a regular app to quit through its normal Quit handler. False if `pid` is not a regular app.
    func gracefulQuit(_ pid: Int32) -> Bool
}

public struct SystemProcessControl: ProcessControl {
    public init() {}

    public func signal(_ pid: Int32, _ sig: Int32) -> Int32 { kill(pid, sig) == 0 ? 0 : errno }

    public func isAlive(_ key: ProcessKey) -> Bool {
        var ri = rusage_info_current()
        let rc = withUnsafeMutablePointer(to: &ri) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(key.pid, RUSAGE_INFO_CURRENT, $0)
            }
        }
        return rc == 0 && ri.ri_proc_start_abstime == key.start
    }

    public func gracefulQuit(_ pid: Int32) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular else { return false }
        return app.terminate()
    }
}

public final class ProcessActions {
    private let control: ProcessControl
    private let selfPid: Int32

    public init(control: ProcessControl = SystemProcessControl(), selfPid: Int32 = getpid()) {
        self.control = control
        self.selfPid = selfPid
    }

    /// Identity of a live process, for callers that did not get it from the sampler.
    public static func key(forPid pid: Int32) -> ProcessKey? {
        var ri = rusage_info_current()
        let rc = withUnsafeMutablePointer(to: &ri) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, $0) }
        }
        return rc == 0 ? ProcessKey(pid: pid, start: ri.ri_proc_start_abstime) : nil
    }

    private func refuses(_ rows: [ProcessRow]) -> Bool {
        rows.contains { Protection.isProtected(pid: $0.pid, name: $0.name, selfPid: selfPid) }
    }

    /// Graceful quit. Apps get their normal Quit (so they can ask to save); helpers are left to exit with
    /// the app. Processes that are not apps get SIGTERM. Waits up to `timeout` for everything to exit.
    public func quit(_ rows: [ProcessRow], timeout: TimeInterval = 5) async -> ActionOutcome {
        guard !refuses(rows) else { return .protected }
        let live = rows.filter { control.isAlive($0.key) }
        if live.isEmpty { return .gone }

        let askedApps = live.filter { control.gracefulQuit($0.pid) }
        var denied = 0, attempted = askedApps.count
        if askedApps.isEmpty {
            attempted = live.count
            for r in live where control.signal(r.pid, SIGTERM) == EPERM { denied += 1 }
        }
        if attempted > 0 && denied == attempted { return .denied }
        return await wait(for: live, timeout: timeout, escalated: false)
    }

    /// SIGKILL every process in the target, then verify they are really gone.
    public func forceQuit(_ rows: [ProcessRow], timeout: TimeInterval = 3) async -> ActionOutcome {
        guard !refuses(rows) else { return .protected }
        let live = rows.filter { control.isAlive($0.key) }
        if live.isEmpty { return .gone }
        var denied = 0
        for r in live where control.signal(r.pid, SIGKILL) == EPERM { denied += 1 }
        if denied == live.count { return .denied }
        return await wait(for: live, timeout: timeout, escalated: true)
    }

    private func wait(for rows: [ProcessRow], timeout: TimeInterval, escalated: Bool) async -> ActionOutcome {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if !rows.contains(where: { control.isAlive($0.key) }) { return .gone }
            if Date() >= deadline { return escalated ? .stuck : .stillRunning }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }
}
