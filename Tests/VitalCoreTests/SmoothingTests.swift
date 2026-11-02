import Testing
import Foundation
@testable import VitalCore

private func t(_ s: Double) -> Date { Date(timeIntervalSince1970: 1_000 + s) }

@Test func meanOverFiveSecondWindow() {
    var m = TimeWindowMean(window: 5)
    var last = 0.0
    for (i, v) in [10.0, 20, 30, 40, 50, 60].enumerated() { last = m.add(v, at: t(Double(i))) }
    #expect(last == 40)               // t=5 keeps t=1...5: 20,30,40,50,60
}

@Test func partialWindowAveragesWhatItHas() {
    var m = TimeWindowMean(window: 5)
    m.add(10, at: t(0))
    #expect(m.add(30, at: t(1)) == 20)
}

@Test func slowCadenceReturnsTheLatestValue() {
    var m = TimeWindowMean(window: 5)
    m.add(10, at: t(0))
    #expect(m.add(90, at: t(5)) == 90)
    #expect(m.add(30, at: t(10)) == 30)
}

@Test func smoothingDampsSpikes() {
    var s = CPUSmoother()
    func reading(_ v: Double) -> CPUReading {
        CPUReading(total: v, perCore: [v], efficiency: v, performance: v, eCount: 0, pCount: 1)
    }
    var out = 0.0
    for (i, v) in [0.2, 0.2, 0.2, 0.2, 1.0].enumerated() { out = s.smooth(reading(v), at: t(Double(i))).total }
    #expect(abs(out - 0.36) < 0.0001)     // a one-second spike to 100% shows as 36%
}

private func row(_ pid: Int32, cpu: Double) -> ProcessRow {
    ProcessRow(key: ProcessKey(pid: pid, start: UInt64(pid)), name: "p\(pid)", path: "/bin/p", cpuCores: cpu)
}

@Test func processFirstSightingIsZeroAndNotCounted() {
    var s = CPUSmoother()
    #expect(s.smooth(rows: [row(1, cpu: 0)], at: t(0))[0].cpuCores == 0)
    #expect(s.smooth(rows: [row(1, cpu: 2)], at: t(1))[0].cpuCores == 2)
    #expect(s.smooth(rows: [row(1, cpu: 4)], at: t(2))[0].cpuCores == 3)
}

@Test func goneProcessesAreForgotten() {
    var s = CPUSmoother()
    _ = s.smooth(rows: [row(1, cpu: 0)], at: t(0))
    _ = s.smooth(rows: [row(1, cpu: 2)], at: t(1))
    _ = s.smooth(rows: [], at: t(2))
    // pid 1 comes back (same key): treated as new again
    #expect(s.smooth(rows: [row(1, cpu: 4)], at: t(3))[0].cpuCores == 0)
}

@Test func shareOfTotalCapacity() {
    #expect(abs(CPUMath.shareOfTotal(cores: 1.85, coreCount: 8) - 0.23125) < 0.0001)
    #expect(CPUMath.shareOfTotal(cores: 1.85, coreCount: 10) == 0.185)
    #expect(abs(CPUMath.shareOfTotal(cores: 6, coreCount: 12) - 0.5) < 0.0001)
    #expect(CPUMath.shareOfTotal(cores: 20, coreCount: 8) == 1)
    #expect(CPUMath.shareOfTotal(cores: 1, coreCount: 0) == 0)
    #expect(CPUMath.shareOfTotal(cores: -1, coreCount: 8) == 0)
}
