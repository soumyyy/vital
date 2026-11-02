import Foundation
import Testing
@testable import VitalCore

private final class Hardware: FanHardware {
    var values: [String: Double] = ["FNum": 1, "F0Md": 0, "F0Mn": 2317, "F0Mx": 6800, "F0Tg": 0]
    var writes: [(String, Double)] = []
    var failKey: String?
    var ignoredKey: String?
    var latchModeWithTarget = false
    private var pendingMode: Double?
    var automaticReadDelay = 0
    private var pendingAutomatic: (value: Double, reads: Int)?
    func number(_ key: String) -> Double? {
        if key == "F0Md", let pending = pendingAutomatic {
            if pending.reads == 0 {
                values[key] = pending.value
                pendingAutomatic = nil
            } else {
                pendingAutomatic = (pending.value, pending.reads - 1)
            }
        }
        return values[key]
    }
    func write(_ key: String, value: Double) throws {
        writes.append((key, value))
        if failKey == key { throw FanSessionError("Rejected") }
        if ignoredKey == key { return }
        if automaticReadDelay > 0 && key == "F0Md" && value != 1 {
            pendingAutomatic = (value, automaticReadDelay)
            return
        }
        if latchModeWithTarget && key == "F0Md" && value == 1 {
            pendingMode = value
            return
        }
        values[key] = value
        if key == "F0Tg", let pendingMode {
            values["F0Md"] = pendingMode
            self.pendingMode = nil
        }
    }
}
private final class Environment {
    var now = 100.0
    var hot = false
    let hardware = Hardware()
    lazy var session = FanSession(hardware: hardware, clock: { self.now }, hot: { self.hot })
}

@Test func helperClampsAndRestoresOriginalAutomaticMode() throws {
    let env = Environment(); env.hardware.values["F0Md"] = 3
    try env.session.set(fan: 0, rpm: 1000)
    #expect(env.hardware.values["F0Tg"] == 2317)
    #expect(env.hardware.values["F0Md"] == 1)
    try env.session.set(fan: 0, rpm: -1)
    #expect(env.hardware.values["F0Md"] == 3)
    #expect(env.session.targets.isEmpty)
}
@Test func helperRejectsInvalidInputsWithoutWriting() {
    for (fan, rpm) in [(0, Double.nan), (0, .infinity), (-1, 4000.0), (8, 4000.0), (1, 4000.0)] {
        let env = Environment()
        #expect(throws: FanSessionError.self) { try env.session.set(fan: fan, rpm: rpm) }
        #expect(env.hardware.writes.isEmpty)
    }
}
@Test func helperRejectsUnknownLimitsAndExistingManualControl() {
    for (key, value) in [("F0Mn", Double.infinity), ("F0Mx", Double.nan), ("F0Md", 1.0)] {
        let env = Environment(); env.hardware.values[key] = value
        #expect(throws: FanSessionError.self) { try env.session.set(fan: 0, rpm: 4000) }
        #expect(env.hardware.writes.isEmpty)
    }
}
@Test func helperRollsBackWhenTargetWriteFails() {
    let env = Environment(); env.hardware.failKey = "F0Tg"
    #expect(throws: FanSessionError.self) { try env.session.set(fan: 0, rpm: 4000) }
    #expect(env.hardware.values["F0Md"] == 0)
    #expect(env.session.targets.isEmpty)
}
@Test func helperLeaseExpiresWithoutHeartbeat() throws {
    let env = Environment(); try env.session.set(fan: 0, rpm: 4000)
    for _ in 0..<8 { env.now += 2; env.session.tick() }
    #expect(env.hardware.values["F0Md"] == 0)
}
@Test func heartbeatKeepsSessionButDoesNotBypassSleepGap() throws {
    let env = Environment(); try env.session.set(fan: 0, rpm: 4000)
    for _ in 0..<10 { env.now += 2; env.session.tick(); env.session.renew() }
    #expect(env.hardware.values["F0Md"] == 1)
    env.now += 11; env.session.renew(); env.session.tick()
    #expect(env.hardware.values["F0Md"] == 0)
}
@Test func thermalPressureResetsAndRejectsManual() throws {
    let env = Environment(); try env.session.set(fan: 0, rpm: 4000)
    env.hot = true; env.session.tick()
    #expect(env.hardware.values["F0Md"] == 0)
    #expect(throws: FanSessionError.self) { try env.session.set(fan: 0, rpm: 4000) }
}
@Test func failedResetIsRetriedAndBlocksFurtherManualChanges() throws {
    let env = Environment(); try env.session.set(fan: 0, rpm: 4000)
    env.hardware.failKey = "F0Md"; env.session.reset()
    #expect(env.session.resetError != nil)
    #expect(env.session.targets[0] == 4000)
    env.now += 1
    #expect(throws: FanSessionError.self) { try env.session.set(fan: 0, rpm: 5000) }
    env.hardware.failKey = nil; env.session.tick()
    #expect(env.session.resetError == nil)
    #expect(env.hardware.values["F0Md"] == 0)
}
@Test func rapidChangesAreRejectedButAutoAlwaysWorks() throws {
    let env = Environment(); try env.session.set(fan: 0, rpm: 4000)
    #expect(throws: FanSessionError.self) { try env.session.set(fan: 0, rpm: 5000) }
    try env.session.set(fan: 0, rpm: -1)
    #expect(env.hardware.values["F0Md"] == 0)
}

@Test func modeIsVerifiedAfterTheCompleteTargetTransaction() throws {
    let env = Environment()
    env.hardware.latchModeWithTarget = true
    try env.session.set(fan: 0, rpm: 4000)
    #expect(env.session.targets[0] == 4000)
    #expect(env.hardware.values["F0Md"] == 1)
}

@Test func firmwareIgnoringATargetIsNotReportedAsSuccess() {
    let env = Environment()
    env.hardware.ignoredKey = "F0Tg"
    #expect(throws: FanSessionError.self) { try env.session.set(fan: 0, rpm: 4000) }
    #expect(env.session.targets.isEmpty)
    #expect(env.hardware.values["F0Md"] == 0)
}

@Test func firmwareIgnoringAutoIsRetriedWithoutClearingManualState() throws {
    let env = Environment()
    try env.session.set(fan: 0, rpm: 4000)
    env.hardware.ignoredKey = "F0Md"
    env.session.reset()
    #expect(env.session.resetError != nil)
    #expect(env.session.targets[0] == 4000)
    env.hardware.ignoredKey = nil
    env.session.tick()
    #expect(env.session.resetError == nil)
    #expect(env.hardware.values["F0Md"] == 0)
}

@Test func unusableFanCountsNeverReachTheWriter() {
    for count in [Double.nan, .infinity, 0, 1.5, 9] {
        let env = Environment()
        env.hardware.values["FNum"] = count
        #expect(throws: FanSessionError.self) { try env.session.set(fan: 0, rpm: 4000) }
        #expect(env.hardware.writes.isEmpty)
    }
}

@Test func autoWaitsForFirmwareReadbackBeforeReportingSuccess() throws {
    let env = Environment()
    try env.session.set(fan: 0, rpm: 4000)
    env.hardware.automaticReadDelay = 3
    try env.session.set(fan: 0, rpm: -1)
    #expect(env.session.targets.isEmpty)
    #expect(env.session.resetError == nil)
    #expect(env.hardware.values["F0Md"] == 0)
}
