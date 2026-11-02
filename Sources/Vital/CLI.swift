import AppKit
import SwiftUI
import Foundation
import VitalCore

/// Command line modes that run instead of the menu bar app. Returns true if one ran.
enum CLI {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments.dropFirst()
        if args.contains("--probe") { probe(); return true }
        if args.contains("--dump-sensors") { dumpSensors(); return true }
        if args.contains("--probe-storage") { probeStorage(); return true }
        if let i = CommandLine.arguments.firstIndex(of: "--render-panel"), i + 1 < CommandLine.arguments.count {
            renderPanel(to: CommandLine.arguments[i + 1]); return true
        }
        if let i = CommandLine.arguments.firstIndex(of: "--dump-icons"), i + 1 < CommandLine.arguments.count {
            dumpIcons(to: CommandLine.arguments[i + 1]); return true
        }
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

    /// Renders the three menu bar glyphs to PNG files (large, on white) for inspection.
    private static func dumpIcons(to dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for (name, band) in [("calm", LoadBand.calm), ("busy", .busy), ("struggling", .struggling)] {
            let icon = PulseIcon.image(for: band)
            let scale = 8
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 18 * scale, pixelsHigh: 18 * scale,
                                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { continue }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 18 * scale, height: 18 * scale).fill()
            icon.draw(in: NSRect(x: 0, y: 0, width: 18 * scale, height: 18 * scale))
            NSGraphicsContext.restoreGraphicsState()
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
        }
    }

    private static func probeStorage() {
        // --workers=N overrides the worker count, for measuring.
        let workers = CommandLine.arguments.first { $0.hasPrefix("--workers=") }.flatMap { Int($0.dropFirst(10)) }
            ?? StorageScanner.defaultConcurrency
        let start = Date()
        var reported = Set<String>()
        let qos: QualityOfService = CommandLine.arguments.contains("--background") ? .background : .utility
        let result = StorageScanner(concurrency: workers, qos: qos).scan(progress: { p in
            for c in p.categories where c.status == .done && !reported.contains(c.name) {
                reported.insert(c.name)
                print(String(format: "%6.1fs  %@ %@%@", Date().timeIntervalSince(start), c.name,
                             Format.bytes(c.bytes, base: .decimal), c.partial ? " (partial)" : ""))
                fflush(stdout)
            }
        })
        guard let r = result, let cap = StorageSampler.capacity() else { return }
        print(String(format: "total %.1fs with %d workers at %@ QoS", Date().timeIntervalSince(start), workers, qos == .background ? "background" : "utility"))
        print("used \(Format.bytes(cap.usedBytes, base: .decimal)), other \(Format.bytes(r.otherBytes(usedBytes: cap.usedBytes), base: .decimal)), partial=\(r.partial), full disk access=\(StorageSampler.hasFullDiskAccess().map { "\($0)" } ?? "unknown")")
        for c in r.categories.sorted(by: { $0.bytes > $1.bytes }).prefix(3) {
            print(c.name, c.top.prefix(3).map { "\(($0.path as NSString).lastPathComponent) \(Format.bytes($0.bytes, base: .decimal))" }.joined(separator: ", "))
        }
    }

    /// Renders the panel into a PNG without a display. Options are listed on `PanelRender`.
    private static func renderPanel(to path: String) {
        MainActor.assumeIsolated { PanelRender.render(to: path) }
    }
}
