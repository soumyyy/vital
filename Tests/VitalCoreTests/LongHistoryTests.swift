import Testing
import Foundation
@testable import VitalCore

private let base = Date(timeIntervalSince1970: 1_800_000_000)       // a whole minute

@Test func readingsInOneMinuteBecomeOneBucketWithMeanAndPeak() {
    var h = LongHistory()
    h.append(0.2, at: base); h.append(0.6, at: base + 20); h.append(0.4, at: base + 40)
    #expect(h.buckets.count == 1)
    #expect(abs(h.buckets[0].mean - 0.4) < 1e-9 && h.buckets[0].peak == 0.6)
    h.append(0.9, at: base + 61)
    #expect(h.buckets.count == 2)
}

@Test func aDayIsKeptAndOlderMinutesAreDropped() {
    var h = LongHistory()
    for m in 0..<(24 * 60 + 30) { h.append(Double(m), at: base + Double(m) * 60) }
    #expect(h.buckets.count == LongHistory.keeping)
    #expect(h.buckets.first?.mean == 30)
}

@Test func clockStepsBackAndBadValuesAreIgnored() {
    var h = LongHistory()
    h.append(1, at: base + 600); h.append(5, at: base); h.append(.nan, at: base + 700); h.append(.infinity, at: base + 800)
    #expect(h.buckets.count == 1 && h.buckets[0].mean == 1)
}

@Test func resamplingAveragesEachStepAndLeavesGapsEmpty() {
    var h = LongHistory()
    for m in 0..<60 { h.append(m < 30 ? 0.2 : 0.8, at: base + Double(m) * 60) }
    let r = h.resampled(window: 3600, buckets: 2, now: base + 3600)
    #expect(r.count == 2 && abs(r[0]! - 0.2) < 1e-9 && abs(r[1]! - 0.8) < 1e-9)
    let early = h.resampled(window: 7200, buckets: 4, now: base + 3600)       // the first hour has no data
    #expect(early[0] == nil && early[1] == nil && early[2] != nil)
    #expect(LongHistory().resampled(window: 60, buckets: 3, now: base).allSatisfy { $0 == nil })
}

@Test func statsCoverOnlyTheRequestedWindow() {
    var h = LongHistory()
    h.append(0.9, at: base)                                                   // outside the last half hour
    for m in 90..<120 { h.append(0.3, at: base + Double(m) * 60) }
    h.append(0.7, at: base + 119 * 60 + 30)
    let s = h.stats(window: 1800, now: base + 120 * 60)
    #expect(s != nil && s!.peak == 0.7 && s!.low < 0.31 && s!.latest > 0.3)
    #expect(h.stats(window: 60, now: base + 10 * 86_400) == nil)
}

@Test func theDayRoundTripsThroughItsFileAndDropsStaleMinutes() throws {
    var all = LongHistories()
    for m in 0..<10 { all.cpu.append(0.1 * Double(m), at: base + Double(m) * 60); all.heat.append(40 + Double(m), at: base + Double(m) * 60) }
    let data = try LongHistoryFile.encode(all)
    let back = try #require(LongHistoryFile.decode(data, now: base + 600))
    #expect(back.cpu.buckets.count == 10 && abs(back.cpu.buckets[3].mean - 0.3) < 1e-4 && back.heat.buckets.count == 10)
    let nextWeek = try #require(LongHistoryFile.decode(data, now: base + 7 * 86_400))
    #expect(nextWeek.isEmpty)
    #expect(LongHistoryFile.decode(Data("nope".utf8)) == nil)
    #expect(LongHistoryFile.decode(Data(#"{"version":99,"series":{}}"#.utf8)) == nil)
}

@Test func savingWritesAtomicallyAndAnEmptyDayWritesNothing() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vital-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("sub/h.json")
    LongHistoryFile.save(LongHistories(), to: url)
    #expect(!FileManager.default.fileExists(atPath: url.path))
    var h = LongHistories(); h.memory.append(0.5, at: base)
    LongHistoryFile.save(h, to: url)
    #expect(LongHistoryFile.load(from: url, now: base)?.memory.buckets.count == 1)
}
