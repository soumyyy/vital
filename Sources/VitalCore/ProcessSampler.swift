import Foundation
import Darwin

public enum ProcessMath {
    /// CPU in cores (1.0 = one core) from cumulative CPU nanoseconds over a wall-clock interval.
    public static func cpuCores(prevNs: UInt64, curNs: UInt64, wallNs: UInt64) -> Double {
        guard wallNs > 0, curNs >= prevNs else { return 0 }
        return Double(curNs - prevNs) / Double(wallNs)
    }

    /// Watts from cumulative nanojoules over a wall-clock interval (nJ per ns is exactly W).
    public static func watts(prevNJ: UInt64, curNJ: UInt64, wallNs: UInt64) -> Double? {
        guard wallNs > 0, curNJ >= prevNJ else { return nil }
        return Double(curNJ - prevNJ) / Double(wallNs)
    }
}

public struct ProcessSample: Sendable {
    public var rows: [ProcessRow]
    public var unreadableCount: Int
}

public final class ProcessSampler {
    private struct Prev { var cpuNs: UInt64; var energyNJ: UInt64 }
    private struct Info { var name: String; var path: String }

    private var previous: [ProcessKey: Prev] = [:]
    private var infoCache: [ProcessKey: Info] = [:]
    private var lastTime: UInt64?
    private let timebase: mach_timebase_info_data_t = {
        var tb = mach_timebase_info_data_t(); mach_timebase_info(&tb); return tb
    }()
    private typealias RespFn = @convention(c) (pid_t) -> pid_t
    private let responsible: RespFn? = {
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(sym, to: RespFn.self)
    }()

    public init() {}

    public func reset() { previous.removeAll(); lastTime = nil }

    private func nanos(_ abs: UInt64) -> UInt64 { abs * UInt64(timebase.numer) / UInt64(timebase.denom) }

    public func sample() -> ProcessSample {
        let now = mach_absolute_time()
        let wallNs = lastTime.map { nanos(now &- $0) } ?? 0
        lastTime = now

        var pids = [pid_t](repeating: 0, count: 4096)
        // proc_listallpids returns the number of pids written (not bytes), unlike proc_listpids.
        let count = max(0, min(pids.count, Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))))

        var rows: [ProcessRow] = []
        var unreadable = 0
        var nextPrev: [ProcessKey: Prev] = [:]
        var liveKeys = Set<ProcessKey>()

        for pid in pids.prefix(count) where pid > 0 {
            var ri = rusage_info_current()
            let rc = withUnsafeMutablePointer(to: &ri) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, $0)
                }
            }
            guard rc == 0 else { unreadable += 1; continue }

            let key = ProcessKey(pid: pid, start: ri.ri_proc_start_abstime)
            liveKeys.insert(key)
            let cpuNs = nanos(ri.ri_user_time &+ ri.ri_system_time)
            let energy = ri.ri_energy_nj
            nextPrev[key] = Prev(cpuNs: cpuNs, energyNJ: energy)

            let info: Info
            if let cached = infoCache[key] { info = cached } else {
                let path = Self.path(pid)
                let name = path.isEmpty ? Self.name(pid) : (path as NSString).lastPathComponent
                info = Info(name: name, path: path)
                infoCache[key] = info
            }

            var cpu = 0.0
            var watts: Double?
            if let p = previous[key] {
                cpu = ProcessMath.cpuCores(prevNs: p.cpuNs, curNs: cpuNs, wallNs: wallNs)
                watts = ProcessMath.watts(prevNJ: p.energyNJ, curNJ: energy, wallNs: wallNs)
            }
            var resp: Int32?
            if let r = responsible?(pid), r > 0, r != pid { resp = r }
            rows.append(ProcessRow(key: key, name: info.name, path: info.path, responsiblePid: resp,
                                   cpuCores: cpu, footprintBytes: ri.ri_phys_footprint, watts: watts))
        }
        previous = nextPrev
        infoCache = infoCache.filter { liveKeys.contains($0.key) }
        return ProcessSample(rows: rows, unreadableCount: unreadable)
    }

    private static func path(_ pid: pid_t) -> String {
        var buf = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let n = proc_pidpath(pid, &buf, UInt32(buf.count))
        return n > 0 ? String(cString: buf) : ""
    }

    private static func name(_ pid: pid_t) -> String {
        var buf = [CChar](repeating: 0, count: 64)
        proc_name(pid, &buf, UInt32(buf.count))
        return String(cString: buf)
    }
}
