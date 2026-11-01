import Testing
import Foundation
@testable import VitalCore

private func t(_ s: Double) -> Date { Date(timeIntervalSince1970: 1_000 + s) }
private func input(cpu: Double = 0.1, pressure: MemoryPressure = .normal,
                   swap: Double = 0, thermal: ThermalState = .nominal) -> LoadInput {
    LoadInput(cpu: cpu, pressure: pressure, swapGrowthBytesPerSec: swap, thermal: thermal)
}

@Test func calmByDefault() {
    var e = LoadEvaluator()
    #expect(e.update(input(), at: t(0)) == .calm)
}

@Test func sustainedHighCPUEntersStrugglingAtTenSeconds() {
    var e = LoadEvaluator()
    for s in 0..<10 { #expect(e.update(input(cpu: 0.95), at: t(Double(s))) != .struggling) }
    #expect(e.update(input(cpu: 0.95), at: t(10)) == .struggling)
}

@Test func leavesStrugglingOnlyAfterTenSecondsClear() {
    var e = LoadEvaluator()
    for s in 0...10 { _ = e.update(input(cpu: 0.95), at: t(Double(s))) }
    #expect(e.update(input(), at: t(11)) == .struggling)
    #expect(e.update(input(), at: t(20)) == .struggling)
    #expect(e.update(input(), at: t(21)) == .calm)
}

@Test func flickeringCPUNeverEntersStruggling() {
    var e = LoadEvaluator()
    for s in 0..<60 {
        let cpu = s % 2 == 0 ? 0.95 : 0.4
        #expect(e.update(input(cpu: cpu), at: t(Double(s))) != .struggling)
    }
}

@Test func criticalPressureAndSeriousThermalEnterImmediately() {
    var a = LoadEvaluator()
    #expect(a.update(input(pressure: .critical), at: t(0)) == .struggling)
    var b = LoadEvaluator()
    #expect(b.update(input(thermal: .serious), at: t(0)) == .struggling)
}

@Test func elevatedSignalsAreBusy() {
    var e = LoadEvaluator()
    #expect(e.update(input(cpu: 0.7), at: t(0)) == .busy)
    var f = LoadEvaluator()
    #expect(f.update(input(pressure: .elevated), at: t(0)) == .busy)
}

@Test func fastSwapGrowthSustainedEntersStruggling() {
    var e = LoadEvaluator()
    for s in 0..<10 { _ = e.update(input(swap: 30_000_000), at: t(Double(s))) }
    #expect(e.update(input(swap: 30_000_000), at: t(10)) == .struggling)
}
