import Testing
import Foundation
@testable import VitalCore

private final class FakeControl: ProcessControl {
    var alive: Set<ProcessKey>
    var diesOn: [Int32: Int32] = [:]       // pid -> signal that kills it
    var signalError: Int32 = 0
    var apps: Set<Int32> = []
    var gracefulMakesDie = true
    var sent: [(Int32, Int32)] = []
    init(alive: [ProcessKey]) { self.alive = Set(alive) }
    func signal(_ pid: Int32, _ sig: Int32) -> Int32 {
        sent.append((pid, sig))
        if signalError != 0 { return signalError }
        if diesOn[pid] == sig, let k = alive.first(where: { $0.pid == pid }) { alive.remove(k) }
        return 0
    }
    func isAlive(_ key: ProcessKey) -> Bool { alive.contains(key) }
    func gracefulQuit(_ pid: Int32) -> Bool {
        guard apps.contains(pid) else { return false }
        if gracefulMakesDie, let k = alive.first(where: { $0.pid == pid }) { alive.remove(k) }
        return true
    }
}

private func row(_ pid: Int32, _ name: String = "thing") -> ProcessRow {
    ProcessRow(key: ProcessKey(pid: pid, start: UInt64(pid)), name: name, path: "/bin/\(name)")
}

@Test func protectedTargetsAreRefusedAndNeverSignaled() async {
    let r = row(321, "WindowServer")
    let c = FakeControl(alive: [r.key])
    let a = ProcessActions(control: c, selfPid: 999)
    #expect(await a.quit([r]) == .protected)
    #expect(await a.forceQuit([r]) == .protected)
    #expect(c.sent.isEmpty)
}

@Test func cannotKillItself() async {
    let r = row(999, "Vital")
    let a = ProcessActions(control: FakeControl(alive: [r.key]), selfPid: 999)
    #expect(await a.forceQuit([r]) == .protected)
}

@Test func quitAsksAppsNotHelpers() async {
    let app = row(10, "Chrome"), helper = row(11, "Chrome Helper")
    let c = FakeControl(alive: [app.key, helper.key]); c.apps = [10]
    c.diesOn[11] = SIGTERM
    let out = await ProcessActions(control: c, selfPid: 999).quit([app, helper], timeout: 0.3)
    #expect(c.sent.isEmpty)                          // helper was not signaled
    #expect(out == .stillRunning)                    // helper still alive, so not reported as gone
}

@Test func quitSignalsPlainProcessesWithSIGTERM() async {
    let p = row(20, "node")
    let c = FakeControl(alive: [p.key]); c.diesOn[20] = SIGTERM
    #expect(await ProcessActions(control: c, selfPid: 999).quit([p]) == .gone)
    #expect(c.sent.first?.1 == SIGTERM)
}

@Test func stubbornProcessReportsStillRunningThenForceQuitWorks() async {
    let p = row(30, "stubborn")
    let c = FakeControl(alive: [p.key]); c.diesOn[30] = SIGKILL
    let a = ProcessActions(control: c, selfPid: 999)
    #expect(await a.quit([p], timeout: 0.3) == .stillRunning)
    #expect(await a.forceQuit([p]) == .gone)
}

@Test func processThatSurvivesSIGKILLIsReportedStuck() async {
    let p = row(40, "wedged")
    let c = FakeControl(alive: [p.key])               // never dies
    #expect(await ProcessActions(control: c, selfPid: 999).forceQuit([p], timeout: 0.3) == .stuck)
}

@Test func permissionErrorsAreReportedAsDenied() async {
    let p = row(50, "rootthing")
    let c = FakeControl(alive: [p.key]); c.signalError = EPERM
    let a = ProcessActions(control: c, selfPid: 999)
    #expect(await a.quit([p]) == .denied)
    #expect(await a.forceQuit([p]) == .denied)
}

@Test func alreadyExitedIsGone() async {
    let p = row(60)
    #expect(await ProcessActions(control: FakeControl(alive: []), selfPid: 999).forceQuit([p]) == .gone)
}

// MARK: real processes

private func spawn(_ script: String) throws -> (Process, ProcessRow) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/sh")
    p.arguments = ["-c", script]
    try p.run()
    usleep(250_000)   // let the exec settle: a process's start time can change until it has exec'd
    let key = ProcessActions.key(forPid: p.processIdentifier)!
    return (p, ProcessRow(key: key, name: "sh", path: "/bin/sh"))
}

@Test func realProcessQuitsOnSIGTERM() async throws {
    let (p, r) = try spawn("sleep 60")
    defer { p.terminate() }
    #expect(await ProcessActions().quit([r], timeout: 3) == .gone)
}

@Test func realProcessIgnoringSIGTERMNeedsForceQuit() async throws {
    let (p, r) = try spawn(#"trap "" TERM; while :; do sleep 1; done"#)
    defer { kill(p.processIdentifier, SIGKILL) }
    let a = ProcessActions()
    #expect(await a.quit([r], timeout: 1) == .stillRunning)
    #expect(await a.forceQuit([r]) == .gone)
}
