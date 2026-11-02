import Foundation

public enum HealthLevel: Int, Comparable, Sendable {
    case good = 0, warning, critical
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

/// The four vitals the panel shows as tiles.
public enum VitalKind: String, CaseIterable, Sendable { case cpu, memory, storage, heat }

/// One sentence about the whole Mac, plus the app the user could quit to fix it.
public struct Headline: Equatable, Sendable {
    public var level: HealthLevel
    public var title: String
    public var detail: String?
    public var focus: VitalKind?          // the tile this is about
    public var culpritID: String?         // app group offered for Quit (never protected, never the aggregate)
    public var hungIDs: [String]          // app groups not responding (never protected)
}

public enum Health {
    /// Memory is being read back from disk fast while a lot is swapped out.
    public static func isThrashing(pageInBytesPerSec: Double, swapUsedBytes: UInt64) -> Bool {
        pageInBytesPerSec > 20_000_000 && swapUsedBytes > 500_000_000
    }

    public static func cpu(_ total: Double) -> HealthLevel {
        total >= LoadEvaluator.cpuStruggleThreshold ? .critical : (total >= LoadEvaluator.cpuBusyThreshold ? .warning : .good)
    }

    public static func memory(_ p: MemoryPressure) -> HealthLevel {
        switch p { case .normal: return .good; case .elevated: return .warning; case .critical: return .critical }
    }

    public static func storage(usedFraction f: Double) -> HealthLevel {
        f >= 0.95 ? .critical : (f >= 0.9 ? .warning : .good)
    }

    /// Follows macOS's own thermal state, so the tile agrees with the headline and the menu bar icon.
    public static func heat(_ s: ThermalState) -> HealthLevel {
        switch s { case .nominal: return .good; case .fair: return .warning; case .serious, .critical: return .critical }
    }

    public static func headline(_ s: Snapshot) -> Headline {
        if s.date == .distantPast {
            return Headline(level: .good, title: "Checking your Mac…", detail: nil, focus: nil, culpritID: nil, hungIDs: [])
        }
        let apps = s.groups.filter { !$0.isAggregate }
        func top(_ metric: RankMetric) -> AppGroup? { Ranking.sorted(apps, by: metric).first }
        func quittable(_ g: AppGroup?) -> String? { g.flatMap { $0.isProtected ? nil : $0.id } }
        func make(_ level: HealthLevel, _ title: String, _ detail: String?, _ focus: VitalKind?, culprit: AppGroup? = nil) -> Headline {
            Headline(level: level, title: title, detail: detail, focus: focus, culpritID: quittable(culprit), hungIDs: [])
        }

        let hung = apps.filter { g in !g.isProtected && g.processes.contains { s.unresponsivePIDs.contains($0.pid) } }
        if !hung.isEmpty {
            let title = hung.count == 1 ? "\(hung[0].name) is not responding" : "\(hung.count) apps are not responding"
            let detail = hung.count == 1 ? "Force Quit it if it does not recover." : "Force Quit them if they do not recover."
            return Headline(level: .critical, title: title, detail: detail, focus: nil, culpritID: nil, hungIDs: hung.map(\.id))
        }

        let cpuTotal = s.cpu?.total ?? 0
        let pressure = s.memory?.pressure ?? .normal
        let thrashing = isThrashing(pageInBytesPerSec: s.pageInBytesPerSec, swapUsedBytes: s.memory?.swapUsedBytes ?? 0)
        let cpuTop = top(.cpu).flatMap { $0.cpuCores >= 0.5 ? $0 : nil }      // an app worth naming
        let memTop = top(.memory)
        let powerTop = top(.power).flatMap { ($0.watts ?? 0) >= 1 ? $0 : nil }

        if s.thermal.state >= .serious {
            return make(.critical, "Your Mac is hot", "It is slowing itself down to cool off.", .heat, culprit: powerTop)
        }
        if pressure == .critical {
            return make(.critical, "Memory is full", memTop.map { "Quitting \($0.name) would free the most." }
                        ?? "The Mac is using the disk as memory, which is slow.", .memory, culprit: memTop)
        }
        if s.band == .struggling {
            if cpuTotal >= LoadEvaluator.cpuBusyThreshold {
                if let app = cpuTop {
                    return make(.critical, "\(app.name) is slowing your Mac", "It is using the most CPU.", .cpu, culprit: app)
                }
                return make(.critical, "Your Mac is struggling", "macOS itself is doing most of the work.", .cpu)
            }
            if thrashing || s.swapGrowthBytesPerSec > 0 {
                return make(.critical, "Your Mac is struggling", "It is short of memory and swapping to disk.", .memory, culprit: memTop)
            }
            return make(.critical, "Your Mac is struggling", "Heavy load for the last few seconds.", nil)
        }

        if cpuTotal >= LoadEvaluator.cpuBusyThreshold {
            return make(.warning, "Your Mac is busy", cpuTop.map { "\($0.name) is using the most CPU." }
                        ?? "macOS itself is doing most of the work.", .cpu, culprit: cpuTop)
        }
        if pressure == .elevated || thrashing {
            return make(.warning, "Memory is getting full", memTop.map { "\($0.name) is using the most." }, .memory, culprit: memTop)
        }
        if s.thermal.state == .fair {
            return make(.warning, "Your Mac is warm", powerTop.map { "\($0.name) is using the most power." }, .heat, culprit: powerTop)
        }
        if let st = s.storage, storage(usedFraction: st.usedFraction) >= .warning {
            return make(.warning, "Storage is almost full", "Free up space to keep your Mac running well.", .storage)
        }
        return make(.good, "Your Mac is running fine", nil, nil)
    }

    /// What is wrong with one vital, for the line shown at the top of that vital's own view. Nil when it is fine.
    public static func status(_ kind: VitalKind, _ s: Snapshot) -> Headline? {
        guard s.date != .distantPast else { return nil }
        let apps = s.groups.filter { !$0.isAggregate }
        func top(_ metric: RankMetric) -> AppGroup? { Ranking.sorted(apps, by: metric).first }
        func quittable(_ g: AppGroup?) -> String? { g.flatMap { $0.isProtected ? nil : $0.id } }
        func make(_ level: HealthLevel, _ title: String, _ detail: String?, culprit: AppGroup? = nil) -> Headline {
            Headline(level: level, title: title, detail: detail, focus: kind, culpritID: quittable(culprit), hungIDs: [])
        }
        switch kind {
        case .cpu:
            let total = s.cpu?.total ?? 0
            guard total >= LoadEvaluator.cpuBusyThreshold else { return nil }
            let app = top(.cpu).flatMap { $0.cpuCores >= 0.5 ? $0 : nil }
            let level = health(forCPU: total)
            if let app { return make(level, level == .critical ? "\(app.name) is slowing your Mac" : "Your Mac is busy", "It is using the most CPU.", culprit: app) }
            return make(level, level == .critical ? "Your Mac is struggling" : "Your Mac is busy", "macOS itself is doing most of the work.")
        case .memory:
            let pressure = s.memory?.pressure ?? .normal
            let thrashing = isThrashing(pageInBytesPerSec: s.pageInBytesPerSec, swapUsedBytes: s.memory?.swapUsedBytes ?? 0)
            guard pressure != .normal || thrashing else { return nil }
            let app = top(.memory)
            if pressure == .critical {
                return make(.critical, "Memory is full", app.map { "Quitting \($0.name) would free the most." }
                            ?? "The Mac is using the disk as memory, which is slow.", culprit: app)
            }
            return make(.warning, "Memory is getting full", app.map { "\($0.name) is using the most." }, culprit: app)
        case .storage:
            guard let st = s.storage else { return nil }
            let level = storage(usedFraction: st.usedFraction)
            guard level > .good else { return nil }
            return make(level, level == .critical ? "Storage is full" : "Storage is almost full",
                        "Free up space to keep your Mac running well.")
        case .heat:
            let level = heat(s.thermal.state)
            guard level > .good else { return nil }
            let app = top(.power).flatMap { ($0.watts ?? 0) >= 1 ? $0 : nil }
            if level == .critical { return make(.critical, "Your Mac is hot", "It is slowing itself down to cool off.", culprit: app) }
            return make(.warning, "Your Mac is warm", app.map { "\($0.name) is using the most power." }, culprit: app)
        }
    }

    private static func health(forCPU total: Double) -> HealthLevel { cpu(total) }
}
