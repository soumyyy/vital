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
        if let m = MemorySampler.sample() {
            print("Memory used \(Format.bytes(m.usedBytes, base: .binary)) of \(Format.bytes(m.totalBytes, base: .binary)), compressed \(Format.bytes(m.compressedBytes, base: .binary)), swap \(Format.bytes(m.swapUsedBytes, base: .binary)) of \(Format.bytes(m.swapTotalBytes, base: .binary)), pressure \(m.pressure)")
        }
    }
}
