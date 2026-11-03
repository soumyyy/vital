import Foundation

/// The `vital` command line: what was asked for, parsed from its arguments. Read-only by design: the CLI reports,
/// it never quits an app or changes a fan.
public struct AgentCommand: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case status
        case apps(by: RankMetric, limit: Int, processes: Bool)
        case history(metric: HistoryMetric, window: TimeInterval)
        case help
        case version
    }
    public var kind: Kind
    public var json: Bool

    public enum ParseError: Error, Equatable, CustomStringConvertible {
        case unknownCommand(String), unknownOption(String), missingValue(String), badValue(option: String, value: String)
        public var description: String {
            switch self {
            case .unknownCommand(let c): return "unknown command '\(c)'"
            case .unknownOption(let o): return "unknown option '\(o)'"
            case .missingValue(let o): return "option '\(o)' needs a value"
            case .badValue(let o, let v): return "'\(v)' is not a valid value for \(o)"
            }
        }
    }

    public static let commandNames = ["status", "apps", "history", "help", "version"]

    /// True when the first argument names a command, or the program was started as `vital` (the lowercase link that
    /// Homebrew installs), so a typo there prints usage instead of opening the menu bar app. A normal launch never lands here.
    public static func isCommand(_ args: [String], invokedAs program: String = "") -> Bool {
        if (program as NSString).lastPathComponent == "vital" { return true }
        guard let first = args.first else { return false }
        return commandNames.contains(first) || ["--help", "-h", "--version"].contains(first)
    }

    public static func parse(_ args: [String]) throws -> AgentCommand {
        var rest = args[...]
        guard let name = rest.popFirst() else { return AgentCommand(kind: .help, json: false) }
        var json = false
        var by: RankMetric = .cpu, limit = 10, processes = false
        var metric: HistoryMetric = .cpu, window: TimeInterval = 3600
        var positional: [String] = []

        func value(_ option: String, _ inline: String?) throws -> String {
            if let inline { return inline }
            guard let v = rest.popFirst() else { throw ParseError.missingValue(option) }
            return v
        }

        while let arg = rest.popFirst() {
            let parts = arg.split(separator: "=", maxSplits: 1).map(String.init)
            let option = parts[0], inline = parts.count > 1 ? parts[1] : nil
            switch option {
            case "--json": json = true
            case "--by" where name == "apps":
                let v = try value(option, inline)
                guard let m = ["cpu": RankMetric.cpu, "memory": .memory, "power": .power, "disk": .disk][v] else { throw ParseError.badValue(option: option, value: v) }
                by = m
            case "-n" where name == "apps", "--limit" where name == "apps":
                let v = try value(option, inline)
                guard let n = Int(v), (1...100).contains(n) else { throw ParseError.badValue(option: option, value: v) }
                limit = n
            case "--processes" where name == "apps": processes = true
            case "--range" where name == "history":
                let v = try value(option, inline)
                guard let w = parseWindow(v) else { throw ParseError.badValue(option: option, value: v) }
                window = w
            case let o where o.hasPrefix("-"): throw ParseError.unknownOption(o)
            default: positional.append(arg)
            }
        }

        switch name {
        case "status": return AgentCommand(kind: .status, json: json)
        case "apps": return AgentCommand(kind: .apps(by: by, limit: limit, processes: processes), json: json)
        case "history":
            if let m = positional.first {
                guard let parsed = HistoryMetric(rawValue: m) else { throw ParseError.badValue(option: "metric", value: m) }
                metric = parsed
            }
            return AgentCommand(kind: .history(metric: metric, window: window), json: json)
        case "help", "--help", "-h": return AgentCommand(kind: .help, json: false)
        case "version", "--version": return AgentCommand(kind: .version, json: json)
        default: throw ParseError.unknownCommand(name)
        }
    }

    /// "90m", "6h", "24h" up to a day. The day on disk has one-minute steps, so shorter than 5 minutes is refused.
    public static func parseWindow(_ text: String) -> TimeInterval? {
        guard let unit = text.last, let n = Double(text.dropLast()), n > 0 else { return nil }
        let seconds = unit == "m" ? n * 60 : (unit == "h" ? n * 3600 : 0)
        return (300...86_400).contains(seconds) ? seconds : nil
    }

    public static let usage = """
    vital: what your Mac is doing, as text or JSON. Read-only.

    Usage:
      vital status [--json]                          CPU, memory, storage, heat, fans, network, battery
      vital apps [--by cpu|memory|power|disk]        Apps ranked by one vital, helpers included
                 [-n 10] [--processes] [--json]
      vital history [cpu|memory|heat|down|up]        The last hours, from the 24 hour record
                    [--range 1h] [--json]            (range: 5m up to 24h, like 90m, 6h, 24h)
      vital help | version

    Notes:
      --json prints one stable object (field "schema" is its version). Absent fields mean "not available".
      History is recorded while Vital is running; it has gaps while the Mac sleeps or Vital is quit.
      Exit status: 0 success, 1 failure, 2 usage error.
    """
}

/// What `vital history` can graph.
public enum HistoryMetric: String, CaseIterable, Sendable {
    case cpu, memory, heat, down, up

    public var unit: String {
        switch self { case .cpu, .memory: return "percent"; case .heat: return "celsius"; case .down, .up: return "bytesPerSecond" }
    }
    /// The recorded figure is a fraction for cpu and memory; the report shows percent.
    public var scale: Double { self == .cpu || self == .memory ? 100 : 1 }

    public func series(of h: LongHistories) -> LongHistory {
        switch self { case .cpu: return h.cpu; case .memory: return h.memory; case .heat: return h.heat; case .down: return h.down; case .up: return h.up }
    }
}
