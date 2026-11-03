import AppKit
import Foundation
import VitalCore

/// `vital status | apps | history`: a read-only report for terminals and AI agents. It samples the Mac itself for about
/// a second, so it works whether or not the menu bar app is running. History comes from the app's 24 hour record.
enum AgentCLI {
    static func runIfRequested(_ args: [String]) -> Bool {
        guard AgentCommand.isCommand(args, invokedAs: CommandLine.arguments.first ?? "") else { return false }
        let command: AgentCommand
        do { command = try AgentCommand.parse(args) } catch {
            FileHandle.standardError.write(Data("vital: \(error)\n\nRun 'vital help' for usage.\n".utf8))
            exit(2)
        }
        switch command.kind {
        case .help: print(AgentCommand.usage)
        case .version: print(command.json ? AgentReport.json(["version": Self.version]) : "vital \(Self.version)")
        case .history(let metric, let window): history(metric, window, json: command.json)
        case .status: report(command) { s in
            command.json ? AgentReport.json(AgentReport.status(s)) : AgentReport.text(AgentReport.status(s)) }
        case .apps(let by, let limit, let processes): report(command) { s in
            let r = AgentReport.apps(s, by: by, limit: limit, processes: processes)
            return command.json ? AgentReport.json(r) : AgentReport.text(r) }
        }
        fflush(stdout)
        return true
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? VitalInfo.version
    }

    private static func history(_ metric: HistoryMetric, _ window: TimeInterval, json: Bool) {
        guard let day = LongHistoryFile.load() else {
            fail("no history yet. Vital records it while the menu bar app runs (\(LongHistoryFile.defaultURL.path)).")
        }
        let r = AgentReport.history(day, metric: metric, window: window, now: Date())
        print(json ? AgentReport.json(r) : AgentReport.text(r))
    }

    /// Takes one live reading (CPU and the app list need two samples, about a second apart) and prints it.
    private static func report(_ command: AgentCommand, _ render: (Snapshot) -> String) {
        let ready = DispatchSemaphore(value: 0)
        let box = Box()
        let sampler = Sampler { snap in
            if snap.hasProcessData, box.take(snap) { ready.signal() }
        }
        sampler.start()
        sampler.setMode(.open)
        guard ready.wait(timeout: .now() + 10) == .success, let snap = box.snapshot else {
            fail("could not read the system in time.")
        }
        sampler.stop()
        print(render(snap))
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("vital: \(message)\n".utf8))
        exit(1)
    }

    /// Holds the first complete reading. Written on the sampler queue, read after the semaphore.
    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Snapshot?
        var snapshot: Snapshot? { lock.lock(); defer { lock.unlock() }; return value }
        func take(_ s: Snapshot) -> Bool {
            lock.lock(); defer { lock.unlock() }
            guard value == nil else { return false }
            value = s
            return true
        }
    }
}
