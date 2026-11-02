import Testing
import Foundation
@testable import VitalCore

// MARK: network

@Test func networkDeltaSumsInterfacesPresentInBoth() {
    let prev = ["en0": (rx: UInt32(1000), tx: UInt32(500))]
    let cur = ["en0": (rx: UInt32(3000), tx: UInt32(800)), "en5": (rx: UInt32(99), tx: UInt32(99))]
    let d = NetworkMath.delta(prev: prev, cur: cur)
    #expect(d.down == 2000 && d.up == 300)       // en5 is new: skipped once
}

@Test func networkDeltaSurvivesCounterWrap() {
    let prev = ["en0": (rx: UInt32.max - 99, tx: UInt32(0))]
    let cur = ["en0": (rx: UInt32(100), tx: UInt32(0))]
    #expect(NetworkMath.delta(prev: prev, cur: cur).down == 200)
}

@Test func onlyPhysicalInterfacesCount() {
    for n in ["en0", "en1", "pdp_ip0"] { #expect(NetworkMath.isPhysical(n)) }
    for n in ["lo0", "utun3", "bridge0", "awdl0", "llw0", "gif0"] { #expect(!NetworkMath.isPhysical(n)) }
}

@Test func rateAndDurationFormats() {
    #expect(Format.rate(0) == "0 B/s")
    #expect(Format.rate(850) == "850 B/s")
    #expect(Format.rate(1_200_000) == "1.2 MB/s")
    #expect(Format.duration(minutes: 70) == "1 h 10 min")
    #expect(Format.duration(minutes: 120) == "2 h")
    #expect(Format.duration(minutes: 45) == "45 min")
}

// MARK: battery (fixtures copied from the owner's M3 MacBook Pro)

private let discharging: [String: Any] = [
    "BatteryInstalled": true, "CurrentCapacity": 18, "MaxCapacity": 100, "CycleCount": 467,
    "IsCharging": false, "ExternalConnected": false, "Voltage": 11130,
    "Amperage": NSNumber(value: UInt64(18446744073709551041)),
    "AvgTimeToEmpty": 70, "TimeRemaining": 70, "AvgTimeToFull": 65535,
    "BatteryData": ["BatteryPower": NSNumber(value: UInt64(18446744073709545217)),
                    "NominalChargeCapacity": 4531, "DesignCapacity": 6075] as [String: Any],
]

@Test func batteryDischargingReadsRealNumbers() {
    let r = BatteryMath.reading(from: discharging)!
    #expect(r.percent == 18 && !r.isCharging && !r.onPower)
    #expect(abs(r.watts! - 6.399) < 0.001)
    #expect(r.minutesRemaining == 70)
    #expect(r.cycleCount == 467)
    #expect(abs(r.healthFraction! - 0.7458) < 0.001)
}

@Test func batteryChargingUsesTimeToFull() {
    var p = discharging
    p["IsCharging"] = true; p["ExternalConnected"] = true; p["AvgTimeToFull"] = 95
    let r = BatteryMath.reading(from: p)!
    #expect(r.isCharging && r.onPower && r.minutesRemaining == 95)
}

@Test func batteryPluggedInAndFullHasNoTimeAndUnknownTimeIsNil() {
    var p = discharging
    p["ExternalConnected"] = true; p["IsCharging"] = false
    #expect(BatteryMath.reading(from: p)!.minutesRemaining == nil)
    var q = discharging
    q["AvgTimeToEmpty"] = 65535; q["TimeRemaining"] = 65535
    #expect(BatteryMath.reading(from: q)!.minutesRemaining == nil)
}

@Test func batteryFallsBackToVoltageTimesAmperageAndHandlesMissingKeys() {
    var p = discharging
    p["BatteryData"] = ["NominalChargeCapacity": 0, "DesignCapacity": 0] as [String: Any]
    let r = BatteryMath.reading(from: p)!
    #expect(abs(r.watts! - 11.13 * 0.575) < 0.01)     // 11130 mV x 575 mA
    #expect(r.healthFraction == nil)
    #expect(BatteryMath.reading(from: [:]) == nil)     // a desktop Mac has no battery
}

// MARK: sleep blockers

@Test func sleepBlockersKeepAppsAndIgnoreThePowerDaemon() {
    let raw: [Int: [[String: Any]]] = [
        359: [["AssertType": "PreventUserIdleSystemSleep", "AssertName": "Powerd - Prevent sleep while display is on"]],
        812: [["AssertType": "PreventUserIdleSystemSleep", "AssertName": "Playing audio"],
              ["AssertType": "PreventUserIdleDisplaySleep", "AssertName": "Playing video"]],
        900: [["AssertType": "ApplePushServiceTask", "AssertName": "push"]],
    ]
    let r = SleepBlockers.parse(raw)
    #expect(Set(r.keys) == [812])
    #expect(r[812]!.reason == "Playing audio" && r[812]!.blocksDisplaySleep)
}

// MARK: wake-ups

@Test func wakeupRateMath() {
    #expect(ProcessMath.perSecond(prev: 100, cur: 600, wallNs: 1_000_000_000) == 500)
    #expect(ProcessMath.perSecond(prev: 100, cur: 600, wallNs: 2_000_000_000) == 250)
    #expect(ProcessMath.perSecond(prev: 600, cur: 100, wallNs: 1_000_000_000) == 0)
    #expect(ProcessMath.perSecond(prev: 1, cur: 2, wallNs: 0) == 0)
}

@Test func wakeupsAreSmoothedAndSummedPerApp() {
    var s = CPUSmoother()
    func row(_ w: Double) -> ProcessRow { ProcessRow(key: ProcessKey(pid: 5, start: 5), name: "x", path: "/bin/x", wakeupsPerSec: w) }
    let t0 = Date(timeIntervalSince1970: 2_000)
    _ = s.smooth(rows: [row(0)], at: t0)
    _ = s.smooth(rows: [row(100)], at: t0 + 1)
    #expect(s.smooth(rows: [row(300)], at: t0 + 2)[0].wakeupsPerSec == 200)
    let groups = Grouping.group([row(30), ProcessRow(key: ProcessKey(pid: 6, start: 6), name: "x", path: "/bin/x", wakeupsPerSec: 70)],
                                systemCPUCores: nil, memoryUsedBytes: nil)
    #expect(groups[0].wakeupsPerSec == 100)
}

@Test func assertionsHeldForAnAppAreAttributedToIt() {
    let held = "app<application.net.whatsapp.WhatsApp.420912218.420912227(501)>420-655-17974:Shared Background Assertion 768 for net.whatsapp.WhatsApp(FinishTask)"
    #expect(SleepBlockers.appName(fromAssertionName: held) == "WhatsApp")
    #expect(SleepBlockers.appName(fromAssertionName: "app<application.com.google.Chrome.123.456(501)>x") == "Chrome")
    #expect(SleepBlockers.appName(fromAssertionName: "Playing audio") == nil)
    let r = SleepBlockers.parse([420: [["AssertType": "PreventUserIdleSystemSleep", "AssertName": held]]])
    #expect(r[420]?.appName == "WhatsApp")
}
