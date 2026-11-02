import Testing
@testable import VitalCore

@Test func targetIsClampedIntoTheFansOwnLimits() {
    #expect(FanSafety.target(requested: 1000, minRPM: 2317, maxRPM: 6800) == 2317)
    #expect(FanSafety.target(requested: 9000, minRPM: 2317, maxRPM: 6800) == 6800)
    #expect(FanSafety.target(requested: 4000, minRPM: 2317, maxRPM: 6800) == 4000)
}

@Test func unusableTargetsAreRejected() {
    #expect(FanSafety.target(requested: .nan, minRPM: 2317, maxRPM: 6800) == nil)
    #expect(FanSafety.target(requested: 4000, minRPM: nil, maxRPM: 6800) == nil)
    #expect(FanSafety.target(requested: 4000, minRPM: 0, maxRPM: 6800) == nil)
    #expect(FanSafety.target(requested: 4000, minRPM: 5000, maxRPM: 4000) == nil)
}
