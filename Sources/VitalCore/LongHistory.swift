import Foundation

/// One number kept for 24 hours as one-minute buckets (mean and peak), so a day costs about 1,440 small values
/// per series however often the sampler runs.
public struct LongHistory: Sendable, Equatable {
    public struct Bucket: Sendable, Equatable {
        public var minute: Int          // whole minutes since 1970
        public var mean: Double
        public var peak: Double
        var count: Int
        public init(minute: Int, mean: Double, peak: Double, count: Int = 1) {
            self.minute = minute; self.mean = mean; self.peak = peak; self.count = count
        }
    }

    public static let keeping = 24 * 60
    public private(set) var buckets: [Bucket] = []
    public init() {}

    static func minute(of date: Date) -> Int { Int((date.timeIntervalSince1970 / 60).rounded(.down)) }

    public mutating func append(_ value: Double, at date: Date) {
        guard value.isFinite else { return }
        let m = Self.minute(of: date)
        if let last = buckets.last {
            if m < last.minute { return }                                  // a clock step back must not scramble the day
            if m == last.minute {
                var b = last
                b.mean = (b.mean * Double(b.count) + value) / Double(b.count + 1)
                b.count += 1
                b.peak = max(b.peak, value)
                buckets[buckets.count - 1] = b
                return
            }
        }
        buckets.append(Bucket(minute: m, mean: value, peak: value))
        let oldest = m - Self.keeping + 1
        if let cut = buckets.firstIndex(where: { $0.minute >= oldest }), cut > 0 { buckets.removeFirst(cut) }
    }

    /// Equal steps ending at `now`, each the mean of the minutes inside it; nil where nothing was recorded.
    public func resampled(window: TimeInterval, buckets steps: Int, now: Date) -> [Double?] {
        guard steps > 0 else { return [] }
        let end = now.timeIntervalSince1970 / 60, span = window / 60
        let step = span / Double(steps)
        var sums = [Double](repeating: 0, count: steps), counts = [Int](repeating: 0, count: steps)
        for b in buckets {
            let age = end - Double(b.minute)                               // minutes before now
            guard age >= 0, age < span else { continue }
            let i = min(steps - 1, Int((span - age) / step))
            sums[i] += b.mean; counts[i] += 1
        }
        return (0..<steps).map { counts[$0] > 0 ? sums[$0] / Double(counts[$0]) : nil }
    }

    public struct Stats: Sendable, Equatable {
        public var mean: Double, peak: Double, low: Double, latest: Double, minutes: Int
    }

    /// Mean, highest and lowest reading over the last `window` seconds, or nil with no data in it.
    public func stats(window: TimeInterval, now: Date) -> Stats? {
        let from = Double(Self.minute(of: now)) - window / 60
        let inside = buckets.filter { Double($0.minute) > from }
        guard let last = inside.last else { return nil }
        let weight = inside.reduce(0) { $0 + $1.count }
        let mean = inside.reduce(0) { $0 + $1.mean * Double($1.count) } / Double(max(1, weight))
        return Stats(mean: mean, peak: inside.map(\.peak).max() ?? last.mean,
                     low: inside.map(\.mean).min() ?? last.mean, latest: last.mean, minutes: inside.count)
    }

    mutating func restore(_ loaded: [Bucket], now: Date) {
        let oldest = Self.minute(of: now) - Self.keeping + 1
        buckets = loaded.filter { $0.minute >= oldest }.sorted { $0.minute < $1.minute }
    }
}

/// A day of the vitals the Overview graphs. Disk is left out: per-app disk rates need the process list,
/// which is only read while the panel is open.
public struct LongHistories: Sendable, Equatable {
    public var cpu = LongHistory()
    public var memory = LongHistory()
    public var heat = LongHistory()
    public var down = LongHistory()
    public var up = LongHistory()
    public init() {}

    public mutating func record(_ s: Snapshot) {
        let d = s.date
        if let c = s.cpu { cpu.append(c.total, at: d) }
        if let m = s.memory { memory.append(m.usedFraction, at: d) }
        if let c = s.thermal.hottestCelsius { heat.append(c, at: d) }
        if let n = s.network { down.append(n.downBytesPerSec, at: d); up.append(n.upBytesPerSec, at: d) }
    }

    public var isEmpty: Bool { cpu.buckets.isEmpty && memory.buckets.isEmpty && heat.buckets.isEmpty }
}

/// The day on disk, so a restart keeps it and the command line can read it. One small JSON file, replaced atomically.
public enum LongHistoryFile {
    public static let version = 1

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Vital", isDirectory: true).appendingPathComponent("history-24h.json")
    }

    private static let names: [(String, WritableKeyPath<LongHistories, LongHistory>)] = [
        ("cpu", \.cpu), ("memory", \.memory), ("heat", \.heat), ("down", \.down), ("up", \.up),
    ]

    public static func encode(_ h: LongHistories) throws -> Data {
        var series: [String: [[Double]]] = [:]
        for (name, path) in names {
            series[name] = h[keyPath: path].buckets.map { [Double($0.minute), ($0.mean * 10_000).rounded() / 10_000, ($0.peak * 10_000).rounded() / 10_000] }
        }
        return try JSONSerialization.data(withJSONObject: ["version": version, "series": series], options: [.sortedKeys])
    }

    public static func decode(_ data: Data, now: Date = Date()) -> LongHistories? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["version"] as? Int == version, let series = root["series"] as? [String: [[Double]]] else { return nil }
        var out = LongHistories()
        for (name, path) in names {
            let buckets = (series[name] ?? []).compactMap { row -> LongHistory.Bucket? in
                guard row.count == 3, row.allSatisfy(\.isFinite) else { return nil }
                return LongHistory.Bucket(minute: Int(row[0]), mean: row[1], peak: row[2])
            }
            out[keyPath: path].restore(buckets, now: now)
        }
        return out
    }

    public static func load(from url: URL = defaultURL, now: Date = Date()) -> LongHistories? {
        (try? Data(contentsOf: url)).flatMap { decode($0, now: now) }
    }

    public static func save(_ h: LongHistories, to url: URL = defaultURL) {
        guard !h.isEmpty, let data = try? encode(h) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

/// How far back the Overview graphs look.
public enum HistoryRange: String, CaseIterable, Sendable, Identifiable {
    case fiveMinutes = "5 min", hour = "1 hr", day = "24 hr"
    public var id: String { rawValue }
    public var window: TimeInterval {
        switch self { case .fiveMinutes: return 300; case .hour: return 3600; case .day: return 86_400 }
    }
    /// "the last hour", for spoken captions.
    public var spoken: String {
        switch self { case .fiveMinutes: return "last 5 minutes"; case .hour: return "last hour"; case .day: return "last 24 hours" }
    }
}
