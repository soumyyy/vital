import SwiftUI
import VitalCore

/// Everything at a glance: a small graph per vital for the last five minutes, plus network and battery.
/// Tapping a card opens that vital's list of apps.
struct OverviewView: View {
    @ObservedObject var model: PanelModel
    private static let window: TimeInterval = 300, buckets = 60

    var body: some View {
        let s = model.snapshot
        let h = model.histories
        let now = s.date == .distantPast ? Date() : s.date
        let series = { (history: History, stale: Bool) -> [Double] in
            history.resampled(window: Self.window, buckets: Self.buckets, now: now, staleAfter: stale ? 6 : nil).compactMap { $0 }
        }
        let layout = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: layout, spacing: 8) {
                cpuCard(s, series(h.cpu, false))
                memoryCard(s, series(h.memory, false))
                diskCard(s, read: series(h.diskRead, true), write: series(h.diskWrite, true))
                networkCard(s, down: series(h.down, true), up: series(h.up, true))
                heatCard(s, series(h.heat, false))
                storageCard(s)
            }
            if let b = s.battery { BatteryCard(battery: b) }
            Text("Graphs show the last five minutes.").font(Typo.small).foregroundStyle(.secondary).padding(.horizontal, 4)
        }
    }

    // MARK: cards

    private func cpuCard(_ s: Snapshot, _ values: [Double]) -> some View {
        let level = s.cpu.map { Health.cpu($0.total) } ?? .good
        return OverviewCard(title: "CPU", value: s.cpu.map { Format.percent($0.total) } ?? "n/a", level: level,
                            caption: Text("In use"), captionSpoken: "in use", open: { model.select(.cpu) }) {
            Sparkline(values: values, color: lineColor(level), slots: Self.buckets)
        }
    }

    private func memoryCard(_ s: Snapshot, _ values: [Double]) -> some View {
        let level = s.memory.map { Health.memory($0.pressure) } ?? .good
        let caption = s.memory.map { "\(Format.bytes($0.usedBytes, base: .binary)) of \(Format.bytes($0.totalBytes, base: .binary))" } ?? ""
        return OverviewCard(title: "Memory", value: s.memory.map { Format.percent($0.usedFraction) } ?? "n/a", level: level,
                            caption: Text(caption), captionSpoken: caption, open: { model.select(.memory) }) {
            Sparkline(values: Self.ranged(values, minSpan: 0.15), color: lineColor(level), slots: Self.buckets)
        }
    }

    private func diskCard(_ s: Snapshot, read: [Double], write: [Double]) -> some View {
        let apps = s.groups.filter { !$0.isAggregate }
        let r = apps.reduce(0) { $0 + $1.diskReadBytesPerSec }, w = apps.reduce(0) { $0 + $1.diskWriteBytesPerSec }
        let top = max(1_000_000, (read + write).max() ?? 0)           // quiet disks stay flat instead of filling the graph
        return OverviewCard(title: "Disk", value: s.hasProcessData ? Format.rate(r + w) : "…", level: .good,
                            caption: Text("●").foregroundColor(Palette.blue) + Text(" \(Format.rate(r))   ") + Text("●").foregroundColor(Palette.orange) + Text(" \(Format.rate(w))"),
                            captionSpoken: "reading \(Format.rate(r)), writing \(Format.rate(w))", open: { model.select(.storage) }) {
            ZStack {
                Sparkline(values: read.map { $0 / top }, color: Palette.blue, filled: false, slots: Self.buckets)
                Sparkline(values: write.map { $0 / top }, color: Palette.orange, filled: false, slots: Self.buckets)
            }
        }
    }

    private func networkCard(_ s: Snapshot, down: [Double], up: [Double]) -> some View {
        let n = s.network
        let top = max(100_000, (down + up).max() ?? 0)
        return OverviewCard(title: "Network", value: n.map { "↓ " + Format.rate($0.downBytesPerSec) } ?? "…", level: .good,
                            caption: Text("●").foregroundColor(Palette.orange) + Text(" ↑ " + (n.map { Format.rate($0.upBytesPerSec) } ?? "")),
                            captionSpoken: "upload " + (n.map { Format.rate($0.upBytesPerSec) } ?? ""), open: nil) {
            ZStack {
                Sparkline(values: down.map { $0 / top }, color: Palette.blue, filled: false, slots: Self.buckets)
                Sparkline(values: up.map { $0 / top }, color: Palette.orange, filled: false, slots: Self.buckets)
            }
        }
    }

    private func heatCard(_ s: Snapshot, _ values: [Double]) -> some View {
        let level = Health.heat(s.thermal.state)
        let value = s.thermal.hottestCelsius.map { "\(Int($0.rounded()))°" } ?? VitalTiles.word(s.thermal.state)
        let scaled = Self.ranged(values, minSpan: 15)
        return OverviewCard(title: "Heat", value: value, level: level,
                            caption: Text(s.thermal.hottestCelsius == nil ? "No temperature sensor" : VitalTiles.word(s.thermal.state)),
                            captionSpoken: VitalTiles.word(s.thermal.state), open: { model.select(.heat) }) {
            Sparkline(values: scaled, color: lineColor(level), slots: Self.buckets)
        }
    }

    private func storageCard(_ s: Snapshot) -> some View {
        let st = s.storage
        let level = st.map { Health.storage(usedFraction: $0.usedFraction) } ?? .good
        return OverviewCard(title: "Storage", value: st.map { Format.percent($0.usedFraction) } ?? "n/a", level: level,
                            caption: Text(st.map { "\(Format.bytes($0.availableBytes, base: .decimal)) free" } ?? ""), captionSpoken: "free space", open: { model.select(.storage) }) {
            VStack { Spacer(minLength: 0); Meter(fraction: st?.usedFraction, level: level).frame(height: 6) }
        }
    }

    /// Stretches a slowly moving series over the graph's height, never by less than `minSpan`, so small changes
    /// do not look like swings.
    static func ranged(_ values: [Double], minSpan: Double) -> [Double] {
        guard let lo = values.min(), let hi = values.max() else { return values }
        let span = max(hi - lo, minSpan)
        let base = lo - (span - (hi - lo)) / 2
        return values.map { ($0 - base) / span * 0.8 + 0.1 }
    }

    private func lineColor(_ level: HealthLevel) -> Color { level == .good ? Color.primary.opacity(0.5) : Palette.color(level) }
}

/// A half-width card: name, one number, a short caption and a graph.
private struct OverviewCard<Graph: View>: View {
    let title: String
    let value: String
    let level: HealthLevel
    let caption: Text
    var captionSpoken = ""
    let open: (() -> Void)?
    @ViewBuilder var graph: Graph

    var body: some View {
        let content = VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Typo.small).foregroundStyle(.secondary)
            Text(value).font(Typo.number).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                .foregroundStyle(level == .good ? Color.primary : Palette.text(level))
            caption.font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            graph.frame(height: 28)
        }
        .frame(maxWidth: .infinity, minHeight: 112, maxHeight: 112, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.055)))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value). \(captionSpoken)")
        if let open { Button(action: open) { content }.buttonStyle(.plain).focusEffectDisabled() } else { content }
    }
}

private struct BatteryCard: View {
    let battery: BatteryReading

    var body: some View {
        let level: HealthLevel = !battery.onPower && battery.percent <= 10 ? .critical : (!battery.onPower && battery.percent <= 20 ? .warning : .good)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Battery").font(Typo.small).foregroundStyle(.secondary)
                Spacer()
                Text(state).font(Typo.small).foregroundStyle(.secondary)
            }
            HStack(alignment: .center, spacing: 10) {
                Text("\(battery.percent)%").font(Typo.number).monospacedDigit()
                    .foregroundStyle(level == .good ? Color.primary : Palette.text(level))
                Meter(fraction: Double(battery.percent) / 100, level: level).frame(height: 6)
            }
            Text(detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.055)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery, \(battery.percent) percent, \(state). \(detail)")
    }

    private var state: String { battery.isCharging ? "Charging" : (battery.onPower ? "Plugged in" : "On battery") }

    private var detail: String {
        var parts: [String] = []
        if let m = battery.minutesRemaining { parts.append((battery.isCharging ? "Full in " : "") + Format.duration(minutes: m) + (battery.isCharging ? "" : " left")) }
        if let w = battery.watts, !battery.onPower || battery.isCharging { parts.append(String(format: "%@ %.1f W", battery.isCharging ? "Charging at" : "Using", w)) }
        if let h = battery.healthFraction { parts.append("Health " + Format.percent(h)) }
        return parts.isEmpty ? " " : parts.joined(separator: " · ")
    }
}
