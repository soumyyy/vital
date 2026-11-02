import Foundation

public struct ProcessKey: Hashable, Sendable {
    public var pid: Int32
    public var start: UInt64          // process start time (mach absolute); survives pid reuse
    public init(pid: Int32, start: UInt64) { self.pid = pid; self.start = start }
}

public struct ProcessRow: Identifiable, Sendable {
    public var key: ProcessKey
    public var name: String
    public var path: String
    public var responsiblePid: Int32?
    public var cpuCores: Double          // 1.0 = one full core, like Activity Monitor's 100%
    public var footprintBytes: UInt64
    public var watts: Double?
    public var wakeupsPerSec: Double      // idle wake-ups: how often the process pulls the CPU out of sleep
    public var diskReadBytesPerSec: Double
    public var diskWriteBytesPerSec: Double
    public var diskWrittenTotal: UInt64   // bytes written since the process started
    public var id: ProcessKey { key }
    public var pid: Int32 { key.pid }
    public init(key: ProcessKey, name: String, path: String, responsiblePid: Int32? = nil,
                cpuCores: Double = 0, footprintBytes: UInt64 = 0, watts: Double? = nil, wakeupsPerSec: Double = 0,
                diskReadBytesPerSec: Double = 0, diskWriteBytesPerSec: Double = 0, diskWrittenTotal: UInt64 = 0) {
        self.diskReadBytesPerSec = diskReadBytesPerSec; self.diskWriteBytesPerSec = diskWriteBytesPerSec
        self.diskWrittenTotal = diskWrittenTotal
        self.key = key; self.name = name; self.path = path; self.responsiblePid = responsiblePid
        self.cpuCores = cpuCores; self.footprintBytes = footprintBytes; self.watts = watts; self.wakeupsPerSec = wakeupsPerSec
    }
}

public struct AppGroup: Identifiable, Sendable {
    public var id: String
    public var name: String
    public var bundlePath: String?
    public var processes: [ProcessRow]
    public var cpuCores: Double
    public var footprintBytes: UInt64
    public var watts: Double?
    public var wakeupsPerSec: Double
    public var diskReadBytesPerSec: Double = 0
    public var diskWriteBytesPerSec: Double = 0
    public var diskWrittenTotal: UInt64 = 0
    public var diskBytesPerSec: Double { diskReadBytesPerSec + diskWriteBytesPerSec }
    public var isProtected: Bool
    public var isAggregate: Bool      // the "System and other users" remainder row
    public init(id: String, name: String, bundlePath: String? = nil, processes: [ProcessRow] = [],
                cpuCores: Double = 0, footprintBytes: UInt64 = 0, watts: Double? = nil, wakeupsPerSec: Double = 0,
                isProtected: Bool = false, isAggregate: Bool = false) {
        self.id = id; self.name = name; self.bundlePath = bundlePath; self.processes = processes
        self.cpuCores = cpuCores; self.footprintBytes = footprintBytes; self.watts = watts; self.wakeupsPerSec = wakeupsPerSec
        self.isProtected = isProtected; self.isAggregate = isAggregate
    }
}

public enum RankMetric: Sendable { case cpu, memory, power, disk }

public enum Ranking {
    public static func sorted(_ groups: [AppGroup], by metric: RankMetric) -> [AppGroup] {
        func value(_ g: AppGroup) -> Double {
            switch metric {
            case .cpu: return g.cpuCores
            case .memory: return Double(g.footprintBytes)
            case .power: return g.watts ?? 0
            case .disk: return g.diskBytesPerSec
            }
        }
        return groups.sorted { value($0) > value($1) }
    }
}
