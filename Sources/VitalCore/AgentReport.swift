import Foundation

/// The data behind `vital`, as plain Codable values (the JSON) and as text. Optional fields are omitted when unknown.
public enum AgentReport {
    public static let schema = 1

    // MARK: models

    public struct Status: Codable, Equatable {
        public struct Summary: Codable, Equatable { public var level: String; public var title: String; public var detail: String? }
        public struct Mac: Codable, Equatable { public var chip: String?; public var model: String?; public var macOS: String }
        public struct CPU: Codable, Equatable { public var percent: Double; public var cores: Int; public var performancePercent: Double?; public var efficiencyPercent: Double? }
        public struct Memory: Codable, Equatable {
            public var percent: Double, usedBytes: UInt64, totalBytes: UInt64, compressedBytes: UInt64
            public var swapUsedBytes: UInt64, pressure: String
        }
        public struct Storage: Codable, Equatable { public var usedPercent: Double, usedBytes: UInt64, availableBytes: UInt64, totalBytes: UInt64 }
        public struct Fan: Codable, Equatable { public var index: Int, rpm: Int; public var minRpm: Int?, maxRpm: Int? }
        public struct Heat: Codable, Equatable {
            public var state: String
            public var hottestCelsius: Double?, cpuCelsius: Double?, gpuCelsius: Double?
            public var fans: [Fan]
        }
        public struct Network: Codable, Equatable { public var downBytesPerSecond: Double, upBytesPerSecond: Double }
        public struct Battery: Codable, Equatable {
            public var percent: Int, charging: Bool, pluggedIn: Bool
            public var minutesRemaining: Int?, watts: Double?, cycleCount: Int?, healthPercent: Double?
        }
        public var schema: Int
        public var generatedAt: String
        public var mac: Mac
        public var summary: Summary
        public var cpu: CPU?
        public var memory: Memory?
        public var storage: Storage?
        public var heat: Heat
        public var network: Network?
        public var battery: Battery?
        public var notResponding: [String]
    }

    public struct Apps: Codable, Equatable {
        public struct Process: Codable, Equatable { public var pid: Int32, name: String, cpuCores: Double, memoryBytes: UInt64 }
        public struct App: Codable, Equatable {
            public var name: String
            public var processCount: Int
            public var cpuPercentOfMac: Double
            public var cpuCores: Double
            public var memoryBytes: UInt64
            public var watts: Double?
            public var diskReadBytesPerSecond: Double, diskWriteBytesPerSecond: Double
            public var notResponding: Bool
            public var protected: Bool
            public var bundlePath: String?
            public var processes: [Process]?
        }
        public struct Other: Codable, Equatable { public var cpuCores: Double, memoryBytes: UInt64 }
        public var schema: Int
        public var generatedAt: String
        public var sortedBy: String
        public var coreCount: Int
        public var totalApps: Int
        public var apps: [App]
        public var systemAndOtherUsers: Other?
    }

    public struct History: Codable, Equatable {
        public struct Stats: Codable, Equatable { public var mean: Double, peak: Double, low: Double, latest: Double }
        public var schema: Int
        public var generatedAt: String
        public var metric: String
        public var unit: String
        public var windowSeconds: Int
        public var stepSeconds: Int
        public var minutesRecorded: Int
        public var stats: Stats?
        public var values: [Double?]      // oldest first; null where nothing was recorded
    }

    // MARK: builders

    static func iso(_ d: Date) -> String { ISO8601DateFormatter().string(from: d) }
    static func round1(_ v: Double) -> Double { (v * 10).rounded() / 10 }
    static func round2(_ v: Double) -> Double { (v * 100).rounded() / 100 }

    public static func status(_ s: Snapshot) -> Status {
        let head = Health.headline(s)
        let level = head.level == .critical ? "critical" : (head.level == .warning ? "warning" : "good")
        let thermal = s.thermal
        return Status(
            schema: schema, generatedAt: iso(s.date),
            mac: .init(chip: Sysctl.string("machdep.cpu.brand_string"), model: Sysctl.string("hw.model"),
                       macOS: ProcessInfo.processInfo.operatingSystemVersionString),
            summary: .init(level: level, title: head.title, detail: head.detail),
            cpu: s.cpu.map { .init(percent: round1($0.total * 100), cores: $0.perCore.count,
                                   performancePercent: $0.performance.map { round1($0 * 100) },
                                   efficiencyPercent: $0.efficiency.map { round1($0 * 100) }) },
            memory: s.memory.map { .init(percent: round1($0.usedFraction * 100), usedBytes: $0.usedBytes, totalBytes: $0.totalBytes,
                                         compressedBytes: $0.compressedBytes, swapUsedBytes: $0.swapUsedBytes,
                                         pressure: ["normal", "elevated", "critical"][$0.pressure.rawValue]) },
            storage: s.storage.map { .init(usedPercent: round1($0.usedFraction * 100), usedBytes: $0.usedBytes,
                                           availableBytes: $0.availableBytes, totalBytes: $0.totalBytes) },
            heat: .init(state: ["nominal", "fair", "serious", "critical"][thermal.state.rawValue],
                        hottestCelsius: thermal.hottestCelsius.map(round1), cpuCelsius: thermal.cpuCelsius.map(round1), gpuCelsius: thermal.gpuCelsius.map(round1),
                        fans: thermal.fans.map { .init(index: $0.index, rpm: Int($0.rpm.rounded()), minRpm: $0.minRPM.map { Int($0.rounded()) }, maxRpm: $0.maxRPM.map { Int($0.rounded()) }) }),
            network: s.network.map { .init(downBytesPerSecond: ($0.downBytesPerSec).rounded(), upBytesPerSecond: ($0.upBytesPerSec).rounded()) },
            battery: s.battery.map { .init(percent: $0.percent, charging: $0.isCharging, pluggedIn: $0.onPower,
                                           minutesRemaining: $0.minutesRemaining, watts: $0.watts.map(round1), cycleCount: $0.cycleCount,
                                           healthPercent: $0.healthFraction.map { round1($0 * 100) }) },
            notResponding: s.groups.filter { g in !g.isAggregate && g.processes.contains { s.unresponsivePIDs.contains($0.pid) } }.map(\.name))
    }

    public static func apps(_ s: Snapshot, by metric: RankMetric, limit: Int, processes: Bool) -> Apps {
        let cores = max(1, s.cpu?.perCore.count ?? 1)
        let real = Ranking.sorted(s.groups.filter { !$0.isAggregate }, by: metric)
        let apps = real.prefix(limit).map { g in
            Apps.App(name: g.name, processCount: g.processes.count,
                     cpuPercentOfMac: round1(CPUMath.shareOfTotal(cores: g.cpuCores, coreCount: cores) * 100), cpuCores: round2(g.cpuCores),
                     memoryBytes: g.footprintBytes, watts: g.watts.map(round2),
                     diskReadBytesPerSecond: g.diskReadBytesPerSec.rounded(), diskWriteBytesPerSecond: g.diskWriteBytesPerSec.rounded(),
                     notResponding: g.processes.contains { s.unresponsivePIDs.contains($0.pid) }, protected: g.isProtected,
                     bundlePath: g.bundlePath,
                     processes: processes ? g.processes.map { .init(pid: $0.pid, name: $0.name, cpuCores: round2($0.cpuCores), memoryBytes: $0.footprintBytes) } : nil)
        }
        let other = s.groups.first { $0.isAggregate }.map { Apps.Other(cpuCores: round2($0.cpuCores), memoryBytes: $0.footprintBytes) }
        return Apps(schema: schema, generatedAt: iso(s.date),
                    sortedBy: ["cpu", "memory", "power", "disk"][[RankMetric.cpu, .memory, .power, .disk].firstIndex(of: metric) ?? 0],
                    coreCount: cores, totalApps: real.count, apps: Array(apps), systemAndOtherUsers: other)
    }

    /// Up to `steps` values across `window`, with the stats of the same span.
    public static func history(_ h: LongHistories, metric: HistoryMetric, window: TimeInterval, now: Date, steps: Int = 48) -> History {
        let series = metric.series(of: h)
        let scale = metric.scale
        let values = series.resampled(window: window, buckets: steps, now: now).map { $0.map { round2($0 * scale) } }
        let st = series.stats(window: window, now: now)
        return History(schema: schema, generatedAt: iso(now), metric: metric.rawValue, unit: metric.unit,
                       windowSeconds: Int(window), stepSeconds: Int(window / Double(steps)),
                       minutesRecorded: st?.minutes ?? 0,
                       stats: st.map { .init(mean: round2($0.mean * scale), peak: round2($0.peak * scale), low: round2($0.low * scale), latest: round2($0.latest * scale)) },
                       values: values)
    }

    // MARK: output

    public static func json<T: Encodable>(_ value: T) -> String {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(data: (try? e.encode(value)) ?? Data("{}".utf8), encoding: .utf8) ?? "{}"
    }

    public static func text(_ r: Status) -> String {
        var out = ["\(r.summary.title)" + (r.summary.detail.map { " \($0)" } ?? "")]
        if let c = r.cpu { out.append(row("CPU", "\(pct(c.percent)) of \(c.cores) cores")) }
        if let m = r.memory {
            out.append(row("Memory", "\(pct(m.percent))  \(Format.bytes(m.usedBytes, base: .binary)) of \(Format.bytes(m.totalBytes, base: .binary)), pressure \(m.pressure), swap \(Format.bytes(m.swapUsedBytes, base: .binary))"))
        }
        if let s = r.storage { out.append(row("Storage", "\(pct(s.usedPercent)) full  \(Format.bytes(s.availableBytes, base: .decimal)) available of \(Format.bytes(s.totalBytes, base: .decimal))")) }
        var heat = r.heat.state
        if let t = r.heat.hottestCelsius { heat += ", hottest \(Int(t.rounded()))°C" }
        if !r.heat.fans.isEmpty { heat += ", fans " + r.heat.fans.map { "\($0.rpm) rpm" }.joined(separator: " / ") }
        out.append(row("Heat", heat))
        if let n = r.network { out.append(row("Network", "↓ \(Format.rate(n.downBytesPerSecond))  ↑ \(Format.rate(n.upBytesPerSecond))")) }
        if let b = r.battery {
            let state = b.charging ? "charging" : (b.pluggedIn ? "plugged in" : (b.minutesRemaining.map { Format.duration(minutes: $0) + " left" } ?? "on battery"))
            out.append(row("Battery", "\(b.percent)%  \(state)"))
        }
        if !r.notResponding.isEmpty { out.append(row("Stuck", r.notResponding.joined(separator: ", ") + " not responding")) }
        return out.joined(separator: "\n")
    }

    public static func text(_ r: Apps) -> String {
        let rows = r.apps.map { a -> [String] in
            [a.name, a.processCount > 1 ? "\(a.processCount) processes" : "1 process",
             pct(a.cpuPercentOfMac), Format.bytes(a.memoryBytes, base: .binary), a.watts.map { String(format: "%.1f W", $0) } ?? "-",
             a.notResponding ? "not responding" : (a.protected ? "protected" : "")]
        }
        let head = ["APP", "PROCESSES", "CPU", "MEMORY", "POWER", ""]
        var out = [table([head] + rows, alignRight: [2, 3, 4])]
        if r.totalApps > r.apps.count { out.append("\(r.totalApps - r.apps.count) more apps. Sorted by \(r.sortedBy); CPU is a share of the whole Mac.") }
        else { out.append("Sorted by \(r.sortedBy); CPU is a share of the whole Mac.") }
        return out.joined(separator: "\n")
    }

    public static func text(_ r: History) -> String {
        guard let s = r.stats else { return "No \(r.metric) history in the last \(spanText(r.windowSeconds)). History is recorded while Vital is running." }
        let u = { (v: Double) in value(v, unit: r.unit) }
        return "\(r.metric) over the last \(spanText(r.windowSeconds))\n\(spark(r.values))\n"
            + "now \(u(s.latest))   average \(u(s.mean))   peak \(u(s.peak))   low \(u(s.low))"
            + (r.minutesRecorded * 60 < r.windowSeconds * 9 / 10 ? "\n(\(r.minutesRecorded) of \(r.windowSeconds / 60) minutes recorded)" : "")
    }

    // MARK: text helpers

    static func pct(_ v: Double) -> String { v == v.rounded() ? "\(Int(v))%" : String(format: "%.1f%%", v) }
    static func row(_ label: String, _ text: String) -> String { label.padding(toLength: 9, withPad: " ", startingAt: 0) + text }

    static func value(_ v: Double, unit: String) -> String {
        switch unit {
        case "percent": return pct(v)
        case "celsius": return "\(Int(v.rounded()))°C"
        default: return Format.rate(v)
        }
    }

    static func spanText(_ seconds: Int) -> String { seconds % 3600 == 0 ? "\(seconds / 3600) h" : "\(seconds / 60) min" }

    static func spark(_ values: [Double?]) -> String {
        let ticks = Array("▁▂▃▄▅▆▇█")
        let real = values.compactMap { $0 }
        guard let lo = real.min(), let hi = real.max() else { return "" }
        return String(values.map { v in
            guard let v else { return " " }
            return hi == lo ? ticks[0] : ticks[min(7, Int((v - lo) / (hi - lo) * 7.999))]
        })
    }

    static func table(_ rows: [[String]], alignRight: Set<Int>) -> String {
        let widths = (0..<(rows.first?.count ?? 0)).map { c in rows.map { $0[c].count }.max() ?? 0 }
        return rows.map { row in
            row.enumerated().map { i, cell in
                let pad = String(repeating: " ", count: widths[i] - cell.count)
                return alignRight.contains(i) ? pad + cell : cell + pad
            }.joined(separator: "  ").trimmingCharacters(in: .whitespaces)
        }.joined(separator: "\n")
    }
}
