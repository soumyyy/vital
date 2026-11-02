import Foundation

/// Recent readings of one number, kept by time so graphs stay honest when the sampling rate changes
/// (every 2 s with the panel open, every 5 to 15 s while closed).
public struct History: Sendable, Equatable {
    public struct Point: Sendable, Equatable { public var time: TimeInterval; public var value: Double }
    public private(set) var points: [Point] = []
    public let keeping: TimeInterval

    public init(keeping: TimeInterval = 600) { self.keeping = keeping }

    public mutating func append(_ value: Double, at date: Date) {
        guard value.isFinite else { return }
        let t = date.timeIntervalSinceReferenceDate
        if let last = points.last, t <= last.time { return }          // a clock step back must not scramble the graph
        points.append(Point(time: t, value: value))
        if let cut = points.firstIndex(where: { $0.time >= t - keeping }), cut > 0 { points.removeFirst(cut) }
    }

    /// Equal time steps ending at `now`. A step before the first reading is nil. With `staleAfter`, a step whose
    /// latest reading is older than that many seconds reads 0 (rates stop when nothing is being measured);
    /// without it, the last reading is held.
    public func resampled(window: TimeInterval = 300, buckets: Int = 60, now: Date, staleAfter: TimeInterval? = nil) -> [Double?] {
        guard buckets > 0, !points.isEmpty else { return Array(repeating: nil, count: max(0, buckets)) }
        let end = now.timeIntervalSinceReferenceDate
        let step = window / Double(buckets)
        var out: [Double?] = []
        var i = 0
        for b in 0..<buckets {
            let at = end - window + step * Double(b + 1)
            while i + 1 < points.count, points[i + 1].time <= at { i += 1 }
            let p = points[i]
            if p.time > at { out.append(nil) }
            else if let stale = staleAfter, at - p.time > stale { out.append(0) }
            else { out.append(p.value) }
        }
        return out
    }
}

/// Everything the Overview page graphs.
public struct Histories: Sendable, Equatable {
    public var cpu = History()
    public var memory = History()
    public var heat = History()
    public var down = History()
    public var up = History()
    public var diskRead = History()
    public var diskWrite = History()
    public init() {}

    public mutating func record(_ s: Snapshot) {
        let d = s.date
        if let c = s.cpu { cpu.append(c.total, at: d) }
        if let m = s.memory { memory.append(m.usedFraction, at: d) }
        if let c = s.thermal.hottestCelsius { heat.append(c, at: d) }
        if let n = s.network { down.append(n.downBytesPerSec, at: d); up.append(n.upBytesPerSec, at: d) }
        if s.hasProcessData {
            let apps = s.groups.filter { !$0.isAggregate }
            diskRead.append(apps.reduce(0) { $0 + $1.diskReadBytesPerSec }, at: d)
            diskWrite.append(apps.reduce(0) { $0 + $1.diskWriteBytesPerSec }, at: d)
        }
    }
}
