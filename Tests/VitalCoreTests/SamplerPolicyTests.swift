import Testing
@testable import VitalCore

@Test func cadenceByMode() {
    #expect(SamplerPolicy.baseInterval(.open) == 1)
    #expect(SamplerPolicy.baseInterval(.closed) == 5)
}

@Test func backsOffWhenTicksAreExpensiveAndRelaxesWhenCheap() {
    var m = 1.0
    m = SamplerPolicy.adapt(multiplier: m, tickDuration: 0.4, base: 1)      // 40% of 1 s
    #expect(m == 2)
    m = SamplerPolicy.adapt(multiplier: m, tickDuration: 1.0, base: 1)      // 50% of 2 s
    #expect(m == 4)
    m = SamplerPolicy.adapt(multiplier: m, tickDuration: 5.0, base: 1)      // capped
    #expect(m == 4)
    m = SamplerPolicy.adapt(multiplier: m, tickDuration: 0.01, base: 1)     // 0.25% of 4 s
    #expect(m == 2)
    m = SamplerPolicy.adapt(multiplier: m, tickDuration: 0.01, base: 1)
    #expect(m == 1)
    #expect(SamplerPolicy.adapt(multiplier: 1, tickDuration: 0.15, base: 1) == 1)   // in the dead band
}

@Test func overlappingTicksAreSkippedNotQueued() {
    var g = TickGate()
    let first = g.begin()
    let second = g.begin()
    let third = g.begin()
    #expect(first && !second && !third)
    #expect(g.skipped == 2)
    g.end()
    let afterEnd = g.begin()
    #expect(afterEnd)
}
