import Foundation
import VitalCore

/// Command line modes that run instead of the menu bar app. Returns true if one ran.
enum CLI {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments.dropFirst()
        if args.contains("--probe") { probe(); return true }
        if args.contains("--dump-sensors") { dumpSensors(); return true }
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

    /// Prints the sensor and fan inventory as JSON so other owners can contribute fixtures for their Macs.
    private static func dumpSensors() {
        let model = { () -> String in
            var size = 0; sysctlbyname("hw.model", nil, &size, nil, 0)
            var buf = [CChar](repeating: 0, count: size); sysctlbyname("hw.model", &buf, &size, nil, 0)
            return String(cString: buf)
        }()
        let chip = { () -> String in
            var size = 0; sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
            var buf = [CChar](repeating: 0, count: size); sysctlbyname("machdep.cpu.brand_string", &buf, &size, nil, 0)
            return String(cString: buf)
        }()
        let r = ThermalSampler.read()
        let dict: [String: Any] = [
            "model": model, "chip": chip, "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "thermalState": "\(r.state)",
            "summary": ["cpu": r.cpuCelsius as Any, "gpu": r.gpuCelsius as Any, "hottest": r.hottestCelsius as Any],
            "sensors": r.sensors.map { ["name": $0.name, "celsius": $0.celsius, "kind": "\($0.kind)"] as [String: Any] },
            "fans": r.fans.map { ["index": $0.index, "rpm": $0.rpm, "min": $0.minRPM as Any, "max": $0.maxRPM as Any] as [String: Any] },
        ]
        let clean = (try? JSONSerialization.data(withJSONObject: dict.mapValues { v -> Any in v }, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]))
        if let data = clean, let text = String(data: data, encoding: .utf8) { print(text) }
    }
}
