import Foundation
import VitalCore

/// Command line modes that run instead of the menu bar app. Returns true if one ran.
enum CLI {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments.dropFirst()
        if args.contains("--probe") { probe(); return true }
        return false
    }

    private static func probe() {
        let cpu = CPUSampler()
        _ = cpu.sample()
        Thread.sleep(forTimeInterval: 1)
        if let r = cpu.sample() {
            print("CPU total \(Format.percent(r.total)) E(\(r.eCount)) \(r.efficiency.map(Format.percent) ?? "n/a") P(\(r.pCount)) \(r.performance.map(Format.percent) ?? "n/a")")
        }
        let ps = ProcessSampler()
        _ = ps.sample()
        Thread.sleep(forTimeInterval: 2)
        let s = ps.sample()
        let cpuNow = cpu.sample()
        let mem = MemorySampler.sample()
        let sysCores = cpuNow.map { $0.total * Double($0.perCore.count) }
        let groups = Grouping.group(s.rows, systemCPUCores: sysCores, memoryUsedBytes: mem?.usedBytes)
        print("processes readable \(s.rows.count), unreadable \(s.unreadableCount)")
        print("-- top by CPU")
        for g in Ranking.sorted(groups, by: .cpu).prefix(6) {
            print(String(format: "%6.0f%%  %@  (%d procs)%@", g.cpuCores * 100, g.name, g.processes.count, g.isAggregate ? " [aggregate]" : ""))
        }
        print("-- top by memory")
        for g in Ranking.sorted(groups, by: .memory).prefix(6) {
            print("\(Format.bytes(g.footprintBytes, base: .binary))  \(g.name)  (\(g.processes.count) procs)")
        }
        print("-- top by power")
        for g in Ranking.sorted(groups, by: .power).prefix(5) {
            print(String(format: "%6.2f W  %@", g.watts ?? 0, g.name))
        }
        if let m = MemorySampler.sample() {
            print("Memory used \(Format.bytes(m.usedBytes, base: .binary)) of \(Format.bytes(m.totalBytes, base: .binary)), compressed \(Format.bytes(m.compressedBytes, base: .binary)), swap \(Format.bytes(m.swapUsedBytes, base: .binary)) of \(Format.bytes(m.swapTotalBytes, base: .binary)), pressure \(m.pressure)")
        }
    }
}
