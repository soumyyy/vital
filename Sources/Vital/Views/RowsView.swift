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
                    let split = c.eCount + c.pCount > 0 ? "\(c.eCount)E + \(c.pCount)P · " : ""
                    header("CPU", "\(split)\(Format.percent(c.total))")
                    Sparkline(values: model.history, color: Palette.level(c.total)).frame(height: 28)
                } else {
                    header("CPU", "Sampling…")
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
                    UsageBar(fraction: s.usedFraction, color: Palette.level(max(0, (s.usedFraction - 0.2) / 0.8 * 0.9)))
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
