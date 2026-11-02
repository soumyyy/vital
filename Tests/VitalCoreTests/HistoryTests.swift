import Testing
import Foundation
@testable import VitalCore

private let t0 = Date(timeIntervalSinceReferenceDate: 1000)

@Test func historyDropsOldAndOutOfOrderReadings() {
    var h = History(keeping: 60)
    h.append(1, at: t0); h.append(2, at: t0 + 30); h.append(3, at: t0 + 100)
    h.append(9, at: t0 + 90)                                   // earlier than the last: ignored
    h.append(.nan, at: t0 + 101)
    #expect(h.points.map(\.value) == [3])                       // 100 s later, only the newest is within 60 s
}

@Test func resamplingHoldsTheLastValueAndLeavesTheStartEmpty() {
    var h = History()
    h.append(0.5, at: t0 + 100); h.append(0.9, at: t0 + 200)
    let r = h.resampled(window: 200, buckets: 4, now: t0 + 250)    // steps end at t0+100, 150, 200, 250
    #expect(r.count == 4)
    #expect(r[0] == 0.5 && r[1] == 0.5 && r[2] == 0.9 && r[3] == 0.9)
    let early = h.resampled(window: 200, buckets: 4, now: t0 + 150)  // steps end at t0+0, 50, 100, 150
    #expect(early[0] == nil && early[1] == nil && early[2] == 0.5)
}

@Test func staleRatesReadZeroInsteadOfBeingHeld() {
    var h = History()
    h.append(500, at: t0 + 10)
    let r = h.resampled(window: 100, buckets: 4, now: t0 + 110, staleAfter: 5)
    #expect(r.compactMap { $0 }.allSatisfy { $0 == 0 })
    #expect(History().resampled(now: t0).allSatisfy { $0 == nil })
}
