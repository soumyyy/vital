import Foundation
import Testing
@testable import VitalCore

@Test func cadenceByMode() {
    #expect(SamplerPolicy.baseInterval(.open) == 2)
    #expect(SamplerPolicy.baseInterval(.open, band: .struggling) == 2)
    #expect(SamplerPolicy.baseInterval(.closed, band: .calm) == 15)
    #expect(SamplerPolicy.baseInterval(.closed, band: .busy) == 5)
    #expect(SamplerPolicy.baseInterval(.closed, band: .struggling) == 5)
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

/// Seconds from opening the panel until the app list has data.
private func secondsUntilAppsAppear(primedFirst: Bool) -> Double {
    let sampler = Sampler { _ in }
    sampler.start()
    Thread.sleep(forTimeInterval: 0.6)
    if primedFirst { sampler.prime(); Thread.sleep(forTimeInterval: 0.6) }
    let opened = Date()
    sampler.setMode(.open)
    while !sampler.latest.hasProcessData && Date().timeIntervalSince(opened) < 5 { Thread.sleep(forTimeInterval: 0.02) }
    let t = Date().timeIntervalSince(opened)
    print("apps after open (primed: \(primedFirst)): \(Int(t * 1000)) ms")
    sampler.stop()
    return t
}

@Test func appListAppearsWithinAFewHundredMillisecondsOfOpening() {
    let cold = secondsUntilAppsAppear(primedFirst: false)
    #expect(cold < 1.2, "cold open took \(cold) s")        // was a full 2 s interval
}

@Test func appListIsReadyImmediatelyAfterAHover() {
    let warm = secondsUntilAppsAppear(primedFirst: true)
    #expect(warm < 0.4, "primed open took \(warm) s")
}
