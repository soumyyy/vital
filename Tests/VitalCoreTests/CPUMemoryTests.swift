import Testing
@testable import VitalCore

private func tk(_ u: UInt32, _ s: UInt32, _ i: UInt32, _ n: UInt32 = 0) -> CoreTicks {
    CoreTicks(user: u, system: s, idle: i, nice: n)
}

@Test func cpuUsageFromDeltas() {
    let prev = [tk(0, 0, 0), tk(0, 0, 0)]
    let cur = [tk(50, 0, 50), tk(0, 0, 100)]
    #expect(CPUMath.usage(prev: prev, cur: cur) == [0.5, 0.0])
}

@Test func cpuUsageHandlesCounterWrap() {
    let prev = [tk(UInt32.max - 9, 0, 0)]
    let cur = [tk(10, 0, 20)]          // user advanced 20 through the wrap, idle 20
    let u = CPUMath.usage(prev: prev, cur: cur)
    #expect(u?.first == 0.5)
}

@Test func cpuUsageRejectsNoElapsedTimeAndMismatchedCores() {
    let a = [tk(5, 5, 5)]
    #expect(CPUMath.usage(prev: a, cur: a) == nil)
    #expect(CPUMath.usage(prev: a, cur: a + a) == nil)
    #expect(CPUMath.usage(prev: [], cur: []) == nil)
}

@Test func cpuSplitsEfficiencyThenPerformance() {
    let r = CPUMath.reading(perCore: [0.1, 0.1, 0.9, 0.9, 0.9, 0.9], eCount: 2, pCount: 4)
    #expect(r.efficiency == 0.1)
    #expect(r.performance == 0.9)
    #expect(abs(r.total - 0.6333333) < 0.0001)
}

@Test func cpuSplitWithoutClusterInfo() {
    let r = CPUMath.reading(perCore: [0.2, 0.4], eCount: 0, pCount: 0)
    #expect(r.efficiency == nil && r.performance == nil)
}

@Test func memoryUsedMatchesActivityMonitorFormula() {
    let s = VMStats(pageSize: 16384, internalPages: 100, purgeablePages: 10, wiredPages: 20, compressorPages: 30)
    #expect(MemoryMath.usedBytes(s) == (90 + 20 + 30) * 16384)
}

@Test func memoryUsedNeverUnderflows() {
    let s = VMStats(pageSize: 16384, internalPages: 5, purgeablePages: 50, wiredPages: 1, compressorPages: 1)
    #expect(MemoryMath.usedBytes(s) == 2 * 16384)
}

@Test func pressureMapping() {
    #expect(MemoryMath.pressure(kernelLevel: 1) == .normal)
    #expect(MemoryMath.pressure(kernelLevel: 2) == .elevated)
    #expect(MemoryMath.pressure(kernelLevel: 4) == .critical)
    #expect(MemoryMath.pressure(kernelLevel: nil) == .normal)
}
