import Foundation
import Darwin

public struct CoreTicks: Equatable, Sendable {
    public var user: UInt32, system: UInt32, idle: UInt32, nice: UInt32
    public init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32) {
        self.user = user; self.system = system; self.idle = idle; self.nice = nice
    }
}

public struct CPUReading: Sendable {
    public var total: Double            // 0...1 across all cores
    public var perCore: [Double]
    public var efficiency: Double?      // average over E cores
    public var performance: Double?     // average over P cores
    public var eCount: Int
    public var pCount: Int
}

public enum CPUMath {
    /// Per-core busy fractions from two tick snapshots. Uses wrapping subtraction (ticks are UInt32).
    /// Returns nil when the snapshots are unusable (different core counts, or no time elapsed on any core).
    public static func usage(prev: [CoreTicks], cur: [CoreTicks]) -> [Double]? {
        guard prev.count == cur.count, !cur.isEmpty else { return nil }
        var out: [Double] = []
        var anyElapsed = false
        for (p, c) in zip(prev, cur) {
            let user = Double(c.user &- p.user), sys = Double(c.system &- p.system)
            let idle = Double(c.idle &- p.idle), nice = Double(c.nice &- p.nice)
            let total = user + sys + idle + nice
            if total > 0 { anyElapsed = true }
            out.append(total > 0 ? min(1, (user + sys + nice) / total) : 0)
        }
        return anyElapsed ? out : nil
    }

    /// Apple Silicon numbers efficiency cores first, then performance cores.
    public static func reading(perCore: [Double], eCount: Int, pCount: Int) -> CPUReading {
        let total = perCore.isEmpty ? 0 : perCore.reduce(0, +) / Double(perCore.count)
        func avg(_ s: ArraySlice<Double>) -> Double? { s.isEmpty ? nil : s.reduce(0, +) / Double(s.count) }
        let e = min(eCount, perCore.count)
        let p = min(e + pCount, perCore.count)
        return CPUReading(total: total, perCore: perCore,
                          efficiency: avg(perCore[0..<e]), performance: avg(perCore[e..<p]),
                          eCount: eCount, pCount: pCount)
    }
}

public final class CPUSampler {
    private var previous: [CoreTicks]?
    public let eCount = Sysctl.int("hw.perflevel1.logicalcpu") ?? 0
    public let pCount = Sysctl.int("hw.perflevel0.logicalcpu") ?? 0

    public init() {}

    /// nil on the first call, after `reset()`, or when the interval is unusable.
    public func sample() -> CPUReading? {
        guard let cur = Self.readTicks() else { return nil }
        defer { previous = cur }
        guard let prev = previous, let usage = CPUMath.usage(prev: prev, cur: cur) else { return nil }
        let (e, p) = (eCount + pCount == cur.count) ? (eCount, pCount) : (0, cur.count)
        return CPUMath.reading(perCore: usage, eCount: e, pCount: p)
    }

    public func reset() { previous = nil }

    static func readTicks() -> [CoreTicks]? {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let kr = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount)
        guard kr == KERN_SUCCESS, let info else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.size))
        }
        let stride = Int(CPU_STATE_MAX)
        return (0..<Int(count)).map { i in
            let base = i * stride
            return CoreTicks(user: UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]),
                             system: UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]),
                             idle: UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]),
                             nice: UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)]))
        }
    }
}
