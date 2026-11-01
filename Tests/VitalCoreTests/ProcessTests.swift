import Testing
@testable import VitalCore

private func row(_ pid: Int32, _ name: String, _ path: String, resp: Int32? = nil,
                 cpu: Double = 0, mem: UInt64 = 0, start: UInt64 = 1) -> ProcessRow {
    ProcessRow(key: ProcessKey(pid: pid, start: start), name: name, path: path,
               responsiblePid: resp, cpuCores: cpu, footprintBytes: mem)
}

@Test func helpersInsideAppGroupUnderOuterApp() {
    let chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    let helper = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/1/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"
    let groups = Grouping.group([row(10, "Google Chrome", chrome, cpu: 0.5),
                                 row(11, "Google Chrome Helper (Renderer)", helper, cpu: 1.0)],
                                systemCPUCores: nil, memoryUsedBytes: nil)
    #expect(groups.count == 1)
    #expect(groups[0].name == "Google Chrome")
    #expect(groups[0].processes.count == 2)
    #expect(groups[0].cpuCores == 1.5)
}

@Test func outOfBundleProcessJoinsResponsibleApp() {
    let safari = row(20, "Safari", "/Applications/Safari.app/Contents/MacOS/Safari")
    let web = row(21, "com.apple.WebKit.WebContent", "/System/Library/Frameworks/WebKit.framework/XPCServices/com.apple.WebKit.WebContent.xpc/Contents/MacOS/com.apple.WebKit.WebContent", resp: 20)
    let groups = Grouping.group([safari, web], systemCPUCores: nil, memoryUsedBytes: nil)
    #expect(groups.count == 1)
    #expect(groups[0].name == "Safari")
}

@Test func plainProcessesGroupByName() {
    let groups = Grouping.group([row(30, "node", "/usr/local/bin/node", cpu: 0.2),
                                 row(31, "node", "/usr/local/bin/node", cpu: 0.3)],
                                systemCPUCores: nil, memoryUsedBytes: nil)
    #expect(groups.count == 1 && groups[0].name == "node" && groups[0].processes.count == 2)
}

@Test func responsibilityCycleDoesNotHang() {
    let a = row(40, "a", "/bin/a", resp: 41)
    let b = row(41, "b", "/bin/b", resp: 40)
    let groups = Grouping.group([a, b], systemCPUCores: nil, memoryUsedBytes: nil)
    #expect(!groups.isEmpty)
}

@Test func aggregateRowHoldsUnexplainedLoadAndNeverGoesNegative() {
    let rows = [row(50, "x", "/bin/x", cpu: 1.0, mem: 100)]
    let g = Grouping.group(rows, systemCPUCores: 3.0, memoryUsedBytes: 1000)
    let agg = g.first { $0.isAggregate }!
    #expect(agg.cpuCores == 2.0 && agg.footprintBytes == 900)
    let over = Grouping.group(rows, systemCPUCores: 0.5, memoryUsedBytes: 10).first { $0.isAggregate }!
    #expect(over.cpuCores == 0 && over.footprintBytes == 0)
}

@Test func protectedProcesses() {
    #expect(Protection.isProtected(pid: 1, name: "launchd", selfPid: 999))
    #expect(Protection.isProtected(pid: 0, name: "kernel_task", selfPid: 999))
    #expect(Protection.isProtected(pid: 321, name: "WindowServer", selfPid: 999))
    #expect(Protection.isProtected(pid: 322, name: "loginwindow", selfPid: 999))
    #expect(Protection.isProtected(pid: 999, name: "Vital", selfPid: 999))
    #expect(!Protection.isProtected(pid: 500, name: "Google Chrome", selfPid: 999))
    let g = Grouping.group([row(322, "loginwindow", "/System/Library/CoreServices/loginwindow.app/Contents/MacOS/loginwindow")],
                           systemCPUCores: nil, memoryUsedBytes: nil, selfPid: 999)
    #expect(g[0].isProtected)
}

@Test func cpuAndPowerDeltaMath() {
    #expect(ProcessMath.cpuCores(prevNs: 0, curNs: 500_000_000, wallNs: 1_000_000_000) == 0.5)
    #expect(ProcessMath.cpuCores(prevNs: 10, curNs: 5, wallNs: 1_000) == 0)      // counter went backwards
    #expect(ProcessMath.cpuCores(prevNs: 0, curNs: 5, wallNs: 0) == 0)
    #expect(ProcessMath.watts(prevNJ: 0, curNJ: 2_000_000_000, wallNs: 1_000_000_000) == 2.0)
    #expect(ProcessMath.watts(prevNJ: 9, curNJ: 1, wallNs: 10) == nil)
}

@Test func rankingSortsByMetric() {
    let a = AppGroup(id: "a", name: "a", cpuCores: 1, footprintBytes: 5)
    let b = AppGroup(id: "b", name: "b", cpuCores: 2, footprintBytes: 1, watts: 3)
    #expect(Ranking.sorted([a, b], by: .cpu).map(\.id) == ["b", "a"])
    #expect(Ranking.sorted([a, b], by: .memory).map(\.id) == ["a", "b"])
    #expect(Ranking.sorted([a, b], by: .power).map(\.id) == ["b", "a"])
}
