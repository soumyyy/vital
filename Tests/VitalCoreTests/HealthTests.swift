import Testing
import Foundation
@testable import VitalCore

private func app(_ name: String, pid: Int32, cpu: Double = 0, mem: UInt64 = 0, watts: Double? = nil, protected: Bool = false) -> AppGroup {
    let row = ProcessRow(key: ProcessKey(pid: pid, start: 1), name: name, path: "/Applications/\(name).app/Contents/MacOS/\(name)",
                         cpuCores: cpu, footprintBytes: mem, watts: watts)
    return AppGroup(id: "app:" + name, name: name, processes: [row], cpuCores: cpu, footprintBytes: mem, watts: watts, isProtected: protected)
}

private func snap(cpu: Double = 0.1, pressure: MemoryPressure = .normal, thermal: ThermalState = .nominal,
                  band: LoadBand = .calm, storageUsed: Double = 0.5, groups: [AppGroup] = [], hung: Set<Int32> = []) -> Snapshot {
    var s = Snapshot.empty
    s.date = Date()
    s.cpu = CPUReading(total: cpu, perCore: Array(repeating: cpu, count: 8), efficiency: nil, performance: nil, eCount: 4, pCount: 4)
    s.memory = MemoryReading(usedBytes: 4 << 30, totalBytes: 8 << 30, compressedBytes: 0, swapUsedBytes: 0, swapTotalBytes: 0, pressure: pressure)
    s.storage = StorageReading(totalBytes: 1000, availableBytes: UInt64(1000 * (1 - storageUsed)))
    s.thermal.state = thermal
    s.band = band
    s.groups = groups + [AppGroup(id: Grouping.aggregateID, name: "System and other users", cpuCores: 5, footprintBytes: 9 << 30,
                                  isProtected: true, isAggregate: true)]
    s.unresponsivePIDs = hung
    s.hasProcessData = true
    return s
}

@Test func calmMacIsFine() {
    let h = Health.headline(snap(groups: [app("Safari", pid: 10, cpu: 0.2)]))
    #expect(h.level == .good)
    #expect(h.title == "Your Mac is running fine")
    #expect(h.culpritID == nil && h.focus == nil)
}

@Test func beforeFirstReadingSaysChecking() {
    #expect(Health.headline(.empty).title == "Checking your Mac…")
}

@Test func hungAppWinsAndIsNamed() {
    let h = Health.headline(snap(cpu: 0.95, band: .struggling, groups: [app("Chrome", pid: 20, cpu: 6), app("Pages", pid: 21)], hung: [21]))
    #expect(h.level == .critical)
    #expect(h.title == "Pages is not responding")
    #expect(h.hungIDs == ["app:Pages"])
}

@Test func protectedHungProcessIsNotOffered() {
    let h = Health.headline(snap(groups: [app("WindowServer", pid: 30, protected: true)], hung: [30]))
    #expect(h.hungIDs.isEmpty)
    #expect(h.level == .good)
}

@Test func strugglingNamesTheTopCPUAppNotTheAggregate() {
    let h = Health.headline(snap(cpu: 0.95, band: .struggling, groups: [app("Chrome", pid: 20, cpu: 3), app("Mail", pid: 22, cpu: 0.1)]))
    #expect(h.title == "Chrome is slowing your Mac")
    #expect(h.culpritID == "app:Chrome")
    #expect(h.focus == .cpu)
}

@Test func strugglingWithOnlySmallAppsBlamesNoApp() {
    let h = Health.headline(snap(cpu: 0.95, band: .struggling, groups: [app("Mail", pid: 22, cpu: 0.2)]))
    #expect(h.title == "Your Mac is struggling")
    #expect(h.culpritID == nil)
}

@Test func busyCPUIsAWarningWithTheCulprit() {
    let h = Health.headline(snap(cpu: 0.7, band: .busy, groups: [app("Xcode", pid: 40, cpu: 4)]))
    #expect(h.level == .warning)
    #expect(h.detail == "Xcode is using the most CPU.")
    #expect(h.culpritID == "app:Xcode")
}

@Test func memoryPressureNamesTheBiggestApp() {
    let elevated = Health.headline(snap(pressure: .elevated, band: .busy, groups: [app("Chrome", pid: 20, mem: 3 << 30), app("Notes", pid: 23, mem: 1 << 30)]))
    #expect(elevated.title == "Memory is getting full")
    #expect(elevated.culpritID == "app:Chrome")
    #expect(elevated.focus == .memory)
    let critical = Health.headline(snap(pressure: .critical, band: .struggling, groups: [app("Chrome", pid: 20, mem: 3 << 30)]))
    #expect(critical.level == .critical && critical.title == "Memory is full")
}

@Test func protectedCulpritIsNamedButNotOffered() {
    let h = Health.headline(snap(cpu: 0.7, band: .busy, groups: [app("kernel_task", pid: 0, cpu: 4, protected: true)]))
    #expect(h.detail == "kernel_task is using the most CPU.")
    #expect(h.culpritID == nil)
}

@Test func heatFollowsThermalState() {
    #expect(Health.headline(snap(thermal: .serious, band: .struggling)).title == "Your Mac is hot")
    #expect(Health.headline(snap(thermal: .fair, band: .busy)).level == .warning)
    #expect(Health.heat(.nominal) == .good && Health.heat(.fair) == .warning && Health.heat(.critical) == .critical)
}

@Test func fullStorageIsTheLastWarning() {
    #expect(Health.headline(snap(storageUsed: 0.93)).title == "Storage is almost full")
    #expect(Health.headline(snap(cpu: 0.7, storageUsed: 0.93)).title == "Your Mac is busy")
    #expect(Health.storage(usedFraction: 0.89) == .good)
    #expect(Health.storage(usedFraction: 0.96) == .critical)
}

@Test func tileLevelsMatchLoadThresholds() {
    #expect(Health.cpu(0.59) == .good)
    #expect(Health.cpu(0.6) == .warning)
    #expect(Health.cpu(0.9) == .critical)
    #expect(Health.memory(.elevated) == .warning)
}

@Test func vitalStatusIsNilWhenFine() {
    let s = snap(groups: [app("Safari", pid: 10, cpu: 0.2)])
    for kind in VitalKind.allCases { #expect(Health.status(kind, s) == nil) }
}

@Test func vitalStatusReportsEachVitalOnItsOwn() {
    let s = snap(cpu: 0.2, pressure: .elevated, thermal: .fair, storageUsed: 0.93,
                 groups: [app("Dia", pid: 10, cpu: 0.2, mem: 4 << 30, watts: 2)])
    #expect(Health.status(.cpu, s) == nil)
    #expect(Health.status(.memory, s)?.title == "Memory is getting full")
    #expect(Health.status(.memory, s)?.culpritID == "app:Dia")
    #expect(Health.status(.storage, s)?.title == "Storage is almost full")
    #expect(Health.status(.storage, s)?.culpritID == nil)
    #expect(Health.status(.heat, s)?.title == "Your Mac is warm")
}

@Test func vitalStatusNeverOffersToQuitProtectedApps() {
    let s = snap(cpu: 0.95, band: .struggling, groups: [app("WindowServer", pid: 30, cpu: 4, protected: true)])
    #expect(Health.status(.cpu, s)?.culpritID == nil)
    #expect(Health.status(.cpu, .empty) == nil)
}
