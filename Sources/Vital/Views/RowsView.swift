import SwiftUI
import VitalCore

struct RowsView: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        VStack(spacing: 8) {
            cpuRow
            memoryRow
            storageRow
            thermalRow
            powerNetworkRow
        }
    }

    private func header(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 12, weight: .semibold))
            Spacer()
            Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private func tappable<V: View>(_ tab: PanelTab, @ViewBuilder _ content: () -> V) -> some View {
        Button { model.tab = tab } label: { content().card().contentShape(Rectangle()) }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .accessibilityElement(children: .combine)
            .accessibilityHint("Shows the \(tab.rawValue) breakdown")
    }

    private var cpuRow: some View {
        tappable(.cpu) {
            VStack(spacing: 6) {
                if let c = model.snapshot.cpu {
                    let cores = c.perCore.count
                    header("CPU", "\(cores) cores · \(Format.percent(c.total)) used")
                    Sparkline(values: model.history, color: Palette.level(c.total)).frame(height: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Using \(Format.coresInUse(c.total * Double(cores), of: cores))")
                        if let p = c.performance, let e = c.efficiency {
                            Text("Performance cores \(Format.percent(p)) · Efficiency cores \(Format.percent(e))")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                } else {
                    header("CPU", "Loading…")
                    Color.clear.frame(height: 28)
                }
            }
        }
    }

    private var memoryRow: some View {
        tappable(.memory) {
            VStack(spacing: 6) {
                if let m = model.snapshot.memory {
                    header("Memory", "\(Format.bytes(m.usedBytes, base: .binary)) / \(Format.bytes(m.totalBytes, base: .binary))")
                    UsageBar(fraction: m.usedFraction, color: pressureColor(m.pressure))
                    HStack {
                        Text(m.swapTotalBytes == 0 ? "No swap" : "Swap \(Format.bytes(m.swapUsedBytes, base: .binary))")
                        Spacer()
                        Text("Pressure: \(pressureWord(m.pressure))").foregroundStyle(pressureColor(m.pressure))
                    }
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    header("Memory", "n/a")
                }
            }
        }
    }

    private var storageRow: some View {
        tappable(.storage) {
            VStack(spacing: 6) {
                if let s = model.snapshot.storage {
                    header("Storage", "\(Format.bytes(s.usedBytes, base: .decimal)) / \(Format.bytes(s.totalBytes, base: .decimal))")
                    UsageBar(fraction: s.usedFraction, color: s.usedFraction < 0.75 ? Palette.green : (s.usedFraction < 0.9 ? Palette.yellow : Palette.red))
                    HStack {
                        Text("\(Format.bytes(s.availableBytes, base: .decimal)) available")
                        Spacer()
                    }
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    header("Storage", "n/a")
                }
            }
        }
    }

    private var thermalRow: some View {
        tappable(.heat) {
            let t = model.snapshot.thermal
            VStack(spacing: 6) {
                if let hot = t.hottestCelsius {
                    header("Thermal", "\(Int(hot.rounded())) °C")
                    ThermalScale(fraction: ThermalMath.scaleFraction(celsius: hot))
                    HStack {
                        Text(sensorSummary(t))
                        Spacer()
                        Text(fanSummary(t))
                    }
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    header("Thermal", stateWord(t.state))
                    ThermalScale(fraction: [ThermalState.nominal: 0.1, .fair: 0.5, .serious: 0.85, .critical: 1][t.state] ?? 0.1)
                    HStack {
                        Text(model.snapshot.date == .distantPast ? "Reading…" : "Temperatures unavailable")
                        Spacer()
                        Text(fanSummary(t))
                    }
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: battery and network

    private var powerNetworkRow: some View {
        tappable(.heat) {
            let snap = model.snapshot
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                    if let b = snap.battery {
                        batteryColumn(b)
                        Divider().opacity(0.5)
                    }
                    networkColumn(snap.network)
                }
                let names = awakeNames
                if !names.isEmpty {
                    Label("Keeping your Mac awake: \(names.joined(separator: ", "))", systemImage: "moon.zzz.fill")
                        .font(.system(size: 11)).foregroundStyle(Palette.orange)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func batteryColumn(_ b: BatteryReading) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Battery").font(.system(size: 12, weight: .semibold))
            HStack(spacing: 4) {
                Text("\(b.percent)%").font(.system(size: 18, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(batteryColor(b))
                if b.isCharging { Image(systemName: "bolt.fill").font(.system(size: 11)).foregroundStyle(Palette.green) }
            }
            ForEach(batteryDetail(b), id: \.self) { line in
                Text(line).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
            }
            if let h = b.healthFraction {
                Text("Health \(Format.percent(h))" + (b.cycleCount.map { " · \($0) cycles" } ?? ""))
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func networkColumn(_ n: NetworkReading?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Network").font(.system(size: 12, weight: .semibold))
            if let n {
                Label(Format.rate(n.downBytesPerSec), systemImage: "arrow.down").foregroundStyle(.primary)
                Label(Format.rate(n.upBytesPerSec), systemImage: "arrow.up").foregroundStyle(.secondary)
            } else {
                Text("Loading…").foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12)).monospacedDigit()
        .labelStyle(NetworkLabelStyle())
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func batteryDetail(_ b: BatteryReading) -> [String] {
        var first = b.isCharging ? "Charging" : (b.onPower ? "Plugged in" : "On battery")
        if let w = b.watts, !b.onPower || b.isCharging { first += String(format: " · %.1f W", w) }
        var lines = [first]
        if let m = b.minutesRemaining { lines.append(Format.duration(minutes: m) + (b.isCharging ? " to full" : " left")) }
        return lines
    }

    private func batteryColor(_ b: BatteryReading) -> Color {
        if b.isCharging || b.onPower { return .primary }
        return b.percent <= 20 ? Palette.red : (b.percent <= 40 ? Palette.yellow : .primary)
    }

    /// Apps holding a "keep the Mac awake" assertion, by app name.
    private var awakeNames: [String] {
        let blockers = model.snapshot.sleepBlockers
        guard !blockers.isEmpty else { return [] }
        let pids = Set(blockers.keys)
        var names = model.snapshot.groups.filter { g in g.processes.contains { pids.contains($0.pid) } }.map(\.name)
        for block in blockers.values {
            let n = block.appName ?? "a background task"
            if !names.contains(n) { names.append(n) }
        }
        return Array(names.prefix(3))
    }

    private func sensorSummary(_ t: ThermalReading) -> String {
        [t.cpuCelsius.map { "CPU \(Int($0.rounded()))°" }, t.gpuCelsius.map { "GPU \(Int($0.rounded()))°" }]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private func fanSummary(_ t: ThermalReading) -> String {
        guard !t.fans.isEmpty else { return "" }
        if t.fans.allSatisfy({ $0.rpm < 1 }) { return "Fan idle" }
        return t.fans.map { Format.rpm($0.rpm) }.joined(separator: " / ")
    }

    private func pressureWord(_ p: MemoryPressure) -> String {
        switch p { case .normal: return "normal"; case .elevated: return "elevated"; case .critical: return "critical" }
    }
    private func pressureColor(_ p: MemoryPressure) -> Color {
        switch p { case .normal: return Palette.green; case .elevated: return Palette.yellow; case .critical: return Palette.red }
    }
    private func stateWord(_ s: ThermalState) -> String {
        switch s { case .nominal: return "Normal"; case .fair: return "Warm"; case .serious: return "Hot"; case .critical: return "Critical" }
    }
}

/// Small arrow icon with fixed width so the speeds line up.
struct NetworkLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.font(.system(size: 9, weight: .bold)).frame(width: 10)
            configuration.title
        }
    }
}
