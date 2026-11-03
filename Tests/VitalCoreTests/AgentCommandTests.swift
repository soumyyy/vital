import Testing
import Foundation
@testable import VitalCore

@Test func commandsParseWithTheirOptions() throws {
    #expect(try AgentCommand.parse(["status"]) == AgentCommand(kind: .status, json: false))
    #expect(try AgentCommand.parse(["status", "--json"]).json)
    #expect(try AgentCommand.parse(["apps"]).kind == .apps(by: .cpu, limit: 10, processes: false))
    #expect(try AgentCommand.parse(["apps", "--by", "memory", "-n", "3", "--processes"]).kind == .apps(by: .memory, limit: 3, processes: true))
    #expect(try AgentCommand.parse(["apps", "--by=power", "--limit=5"]).kind == .apps(by: .power, limit: 5, processes: false))
    #expect(try AgentCommand.parse(["history"]).kind == .history(metric: .cpu, window: 3600))
    #expect(try AgentCommand.parse(["history", "heat", "--range", "24h"]).kind == .history(metric: .heat, window: 86_400))
    #expect(try AgentCommand.parse([]).kind == .help)
}

@Test func badInputIsRefusedWithAReason() {
    #expect(throws: AgentCommand.ParseError.unknownCommand("nope")) { try AgentCommand.parse(["nope"]) }
    #expect(throws: AgentCommand.ParseError.unknownOption("--frobnicate")) { try AgentCommand.parse(["status", "--frobnicate"]) }
    #expect(throws: AgentCommand.ParseError.unknownOption("--by")) { try AgentCommand.parse(["status", "--by", "cpu"]) }
    #expect(throws: AgentCommand.ParseError.missingValue("--by")) { try AgentCommand.parse(["apps", "--by"]) }
    #expect(throws: AgentCommand.ParseError.badValue(option: "--by", value: "colour")) { try AgentCommand.parse(["apps", "--by", "colour"]) }
    #expect(throws: AgentCommand.ParseError.badValue(option: "-n", value: "0")) { try AgentCommand.parse(["apps", "-n", "0"]) }
    #expect(throws: AgentCommand.ParseError.badValue(option: "--range", value: "2d")) { try AgentCommand.parse(["history", "--range", "2d"]) }
    #expect(throws: AgentCommand.ParseError.badValue(option: "metric", value: "gpu")) { try AgentCommand.parse(["history", "gpu"]) }
}

@Test func rangesAreBetweenFiveMinutesAndADay() {
    #expect(AgentCommand.parseWindow("90m") == 5400 && AgentCommand.parseWindow("6h") == 21_600)
    #expect(AgentCommand.parseWindow("1m") == nil && AgentCommand.parseWindow("25h") == nil && AgentCommand.parseWindow("h") == nil)
}

@Test func onlyCommandsOrTheLowercaseLinkRunTheCLI() {
    #expect(!AgentCommand.isCommand([], invokedAs: "/Applications/Vital.app/Contents/MacOS/Vital"))
    #expect(!AgentCommand.isCommand(["-psn_0_1234"], invokedAs: "/Applications/Vital.app/Contents/MacOS/Vital"))
    #expect(AgentCommand.isCommand(["status"], invokedAs: "Vital"))
    #expect(AgentCommand.isCommand(["whatever"], invokedAs: "/opt/homebrew/bin/vital"))
}

@Test func historyReportScalesFractionsToPercentAndFlagsGaps() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var all = LongHistories()
    for m in 0..<30 { all.cpu.append(0.5, at: now - Double(30 - m) * 60) }
    let r = AgentReport.history(all, metric: .cpu, window: 3600, now: now, steps: 6)
    #expect(r.unit == "percent" && r.stepSeconds == 600 && r.values.count == 6)
    #expect(r.values.first! == nil && r.values.last! == 50)
    #expect(r.stats?.peak == 50 && r.minutesRecorded == 30)
    #expect(AgentReport.text(r).contains("30 of 60 minutes recorded"))
    #expect(AgentReport.history(LongHistories(), metric: .heat, window: 3600, now: now).stats == nil)
}

@Test func appsReportRanksGroupsAndKeepsSystemSeparate() {
    func g(_ name: String, cores: Double, mem: UInt64, procs: Int) -> AppGroup {
        let rows = (0..<procs).map { ProcessRow(key: ProcessKey(pid: Int32($0 + 100), start: 1), name: name, path: "/Apps/\(name).app/x", cpuCores: cores / Double(procs), footprintBytes: mem / UInt64(procs)) }
        return AppGroup(id: "app:" + name, name: name, bundlePath: "/Apps/\(name).app", processes: rows, cpuCores: cores, footprintBytes: mem)
    }
    var s = Snapshot.empty
    s.date = Date(timeIntervalSince1970: 1_800_000_000)
    s.groups = [g("Small", cores: 0.1, mem: 100, procs: 1), g("Browser", cores: 2, mem: 4000, procs: 4),
                AppGroup(id: Grouping.aggregateID, name: "System and other users", cpuCores: 1, footprintBytes: 9, isProtected: true, isAggregate: true)]
    let r = AgentReport.apps(s, by: .memory, limit: 1, processes: true)
    #expect(r.apps.map(\.name) == ["Browser"] && r.totalApps == 2 && r.apps[0].processCount == 4 && r.apps[0].processes?.count == 4)
    #expect(r.systemAndOtherUsers?.memoryBytes == 9)
    let text = AgentReport.text(r)
    #expect(text.contains("4 processes") && text.contains("1 more apps"))
    #expect(AgentReport.apps(s, by: .cpu, limit: 5, processes: false).apps[0].processes == nil)
}

@Test func jsonIsStableSortedAndCarriesTheSchemaVersion() throws {
    let json = AgentReport.json(AgentReport.history(LongHistories(), metric: .cpu, window: 3600, now: Date(timeIntervalSince1970: 0)))
    let obj = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    #expect(obj["schema"] as? Int == AgentReport.schema && obj["metric"] as? String == "cpu")
    #expect(!json.contains("\\/"))
}
