import Foundation

/// Mean of the values added within the last `window` seconds. The newest value is always kept, so with a
/// slow cadence (one sample every 5 s while the panel is closed) it simply returns the latest value.
public struct TimeWindowMean {
    public let window: TimeInterval
    private var samples: [(time: Date, value: Double)] = []

    public init(window: TimeInterval = 5) { self.window = window }

    @discardableResult
    public mutating func add(_ value: Double, at now: Date) -> Double {
        samples.append((now, value))
        samples.removeAll { now.timeIntervalSince($0.time) >= window && $0.time != now }
        return samples.reduce(0) { $0 + $1.value } / Double(samples.count)
    }
}

/// Smooths CPU numbers over a 5 s window so the display does not jump around.
public struct CPUSmoother {
    public static let window: TimeInterval = 5

    private var total = TimeWindowMean(window: window)
    private var efficiency = TimeWindowMean(window: window)
    private var performance = TimeWindowMean(window: window)
    private var perProcess: [ProcessKey: TimeWindowMean] = [:]
    private var perProcessWake: [ProcessKey: TimeWindowMean] = [:]
    private var seen = Set<ProcessKey>()

    public init() {}

    public mutating func smooth(_ r: CPUReading, at now: Date) -> CPUReading {
        var out = r
        out.total = total.add(r.total, at: now)
        if let e = r.efficiency { out.efficiency = efficiency.add(e, at: now) }
        if let p = r.performance { out.performance = performance.add(p, at: now) }
        return out
    }

    /// Per-process smoothing. A process's first sighting has no CPU delta yet, so it reports 0 and is not
    /// counted in the mean. Entries for processes that have gone are dropped.
    public mutating func smooth(rows: [ProcessRow], at now: Date) -> [ProcessRow] {
        var live = Set<ProcessKey>()
        let out: [ProcessRow] = rows.map { row in
            var r = row
            live.insert(row.key)
            if seen.contains(row.key) {
                var mean = perProcess[row.key] ?? TimeWindowMean(window: Self.window)
                r.cpuCores = mean.add(row.cpuCores, at: now)
                perProcess[row.key] = mean
                var wake = perProcessWake[row.key] ?? TimeWindowMean(window: Self.window)
                r.wakeupsPerSec = wake.add(row.wakeupsPerSec, at: now)
                perProcessWake[row.key] = wake
            } else {
                seen.insert(row.key)
                r.cpuCores = 0
                r.wakeupsPerSec = 0
            }
            return r
        }
        seen = seen.intersection(live)
        perProcess = perProcess.filter { live.contains($0.key) }
        perProcessWake = perProcessWake.filter { live.contains($0.key) }
        return out
    }

    public mutating func resetProcesses() { perProcess.removeAll(); perProcessWake.removeAll(); seen.removeAll() }
    public mutating func reset() { self = CPUSmoother() }
}
