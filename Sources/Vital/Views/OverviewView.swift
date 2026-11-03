import SwiftUI
import VitalCore

/// Everything at a glance: a small graph per vital for the last 5 minutes, hour or day, plus network and battery.
/// Tapping a card opens that vital's list of apps.
struct OverviewView: View {
    @ObservedObject var model: PanelModel
    private static let buckets = 60

    var body: some View {
        let s = model.snapshot
        let h = model.histories
        let now = s.date == .distantPast ? Date() : s.date
        let range = model.range, long = model.longHistories
        let live = range == .fiveMinutes
        let series = { (history: History, day: LongHistory, stale: Bool) -> [Double] in
            live ? history.resampled(window: range.window, buckets: Self.buckets, now: now, staleAfter: stale ? 6 : nil).compactMap { $0 }
                 : day.resampled(window: range.window, buckets: Self.buckets, now: now).compactMap { $0 }
        }
        let layout = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        VStack(alignment: .leading, spacing: 8) {
            RangePicker(range: $model.range)
            LazyVGrid(columns: layout, spacing: 8) {
                cpuCard(s, series(h.cpu, long.cpu, false), stats: stats(long.cpu, range, now))
                memoryCard(s, series(h.memory, long.memory, false), stats: stats(long.memory, range, now))
                diskCard(s, read: live ? series(h.diskRead, long.cpu, true) : [], write: live ? series(h.diskWrite, long.cpu, true) : [], live: live)
                heatCard(s, series(h.heat, long.heat, false), stats: stats(long.heat, range, now))
            }
            thinRows(s, down: series(h.down, long.down, true), up: series(h.up, long.up, true))
        }
    }

    /// Average and highest reading over a long range; nil on the live 5 minute view, which shows the current figure instead.
    private func stats(_ h: LongHistory, _ range: HistoryRange, _ now: Date) -> LongHistory.Stats? {
        range == .fiveMinutes ? nil : h.stats(window: range.window, now: now)
    }

    // MARK: cards

    private func cpuCard(_ s: Snapshot, _ values: [Double], stats: LongHistory.Stats?) -> some View {
        let level = s.cpu.map { Health.cpu($0.total) } ?? .good
        return OverviewCard(title: "CPU", value: s.cpu.map { Format.percent($0.total) } ?? "n/a", level: level,
                            caption: Text(stats.map { "avg \(Format.percent($0.mean)) · peak \(Format.percent($0.peak))" } ?? "In use"),
                            captionSpoken: stats.map { "average \(Format.percent($0.mean)), peak \(Format.percent($0.peak)) over the \(model.range.spoken)" } ?? "in use", open: { model.select(.cpu) }) {
            Sparkline(values: values, color: lineColor(level), slots: Self.buckets)
        }
    }

    private func memoryCard(_ s: Snapshot, _ values: [Double], stats: LongHistory.Stats?) -> some View {
        let level = s.memory.map { Health.memory($0.pressure) } ?? .good
        let caption = stats.map { "avg \(Format.percent($0.mean)) · peak \(Format.percent($0.peak))" }
            ?? s.memory.map { "\(Format.bytes($0.usedBytes, base: .binary)) of \(Format.bytes($0.totalBytes, base: .binary))" } ?? ""
        return OverviewCard(title: "Memory", value: s.memory.map { Format.percent($0.usedFraction) } ?? "n/a", level: level,
                            caption: Text(caption), captionSpoken: caption, open: { model.select(.memory) }) {
            Sparkline(values: Self.ranged(values, minSpan: 0.15), color: lineColor(level), slots: Self.buckets)
        }
    }

    private func diskCard(_ s: Snapshot, read: [Double], write: [Double], live: Bool) -> some View {
        let apps = s.groups.filter { !$0.isAggregate }
        let r = apps.reduce(0) { $0 + $1.diskReadBytesPerSec }, w = apps.reduce(0) { $0 + $1.diskWriteBytesPerSec }
        let top = max(1_000_000, (read + write).max() ?? 0)           // quiet disks stay flat instead of filling the graph
        return OverviewCard(title: "Disk", value: s.hasProcessData ? Format.rate(r + w) : "…", level: .good,
                            caption: Text("●").foregroundColor(Palette.blue) + Text(" \(Format.rate(r))   ") + Text("●").foregroundColor(Palette.orange) + Text(" \(Format.rate(w))"),
                            captionSpoken: "reading \(Format.rate(r)), writing \(Format.rate(w))", open: { model.select(.storage) }) {
            if live {
                ZStack {
                    Sparkline(values: read.map { $0 / top }, color: Palette.blue, filled: false, slots: Self.buckets)
                    Sparkline(values: write.map { $0 / top }, color: Palette.orange, filled: false, slots: Self.buckets)
                }
            } else {
                Text("Graphed for 5 min only").font(.system(size: 10)).foregroundStyle(.tertiary)      // per-app disk is read only while the panel is open
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func heatCard(_ s: Snapshot, _ values: [Double], stats: LongHistory.Stats?) -> some View {
        let level = Health.heat(s.thermal.state)
        let value = s.thermal.hottestCelsius.map { "\(Int($0.rounded()))°" } ?? VitalTiles.word(s.thermal.state)
        let scaled = Self.ranged(values, minSpan: 15)
        return OverviewCard(title: "Heat", value: value, level: level,
                            caption: Text(stats.map { "avg \(Int($0.mean.rounded()))° · peak \(Int($0.peak.rounded()))°" }
                                          ?? (s.thermal.hottestCelsius == nil ? "No temperature sensor" : VitalTiles.word(s.thermal.state))),
                            captionSpoken: stats.map { "average \(Int($0.mean.rounded())) degrees, peak \(Int($0.peak.rounded())) over the \(model.range.spoken)" } ?? VitalTiles.word(s.thermal.state), open: { model.select(.heat) }) {
            Sparkline(values: scaled, color: lineColor(level), slots: Self.buckets)
        }
    }

    /// Storage, network and battery need one line each.
    private func thinRows(_ s: Snapshot, down: [Double], up: [Double]) -> some View {
        let st = s.storage
        let storageLevel = st.map { Health.storage(usedFraction: $0.usedFraction) } ?? .good
        let top = max(100_000, (down + up).max() ?? 0)
        return VStack(spacing: 0) {
            ThinRow(title: "Storage", value: st.map { "\(Format.percent($0.usedFraction)) · \(Format.bytes($0.availableBytes, base: .decimal)) free" } ?? "n/a",
                    level: storageLevel, open: { model.select(.storage) }) {
                Meter(fraction: st?.usedFraction, level: storageLevel).frame(height: 4)
            }
            if let n = s.network {
                ThinRow(title: "Network", value: "↓ \(Format.rate(n.downBytesPerSec)) ↑ \(Format.rate(n.upBytesPerSec))", level: .good, open: nil) {
                    ZStack {
                        Sparkline(values: down.map { $0 / top }, color: Palette.blue, filled: false, slots: Self.buckets)
                        Sparkline(values: up.map { $0 / top }, color: Palette.orange, filled: false, slots: Self.buckets)
                    }.frame(height: 16)
                }
            }
            if let b = s.battery {
                let level: HealthLevel = !b.onPower && b.percent <= 10 ? .critical : (!b.onPower && b.percent <= 20 ? .warning : .good)
                let state = b.isCharging ? "charging" : (b.onPower ? "plugged in" : (b.minutesRemaining.map { Format.duration(minutes: $0) + " left" } ?? "on battery"))
                ThinRow(title: "Battery", value: "\(b.percent)% · \(state)", level: level, open: nil) {
                    Meter(fraction: Double(b.percent) / 100, level: level).frame(height: 4)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.055)))
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
            Text(value).font(Font.system(size: 18, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                .foregroundStyle(level == .good ? Color.primary : Palette.text(level))
            caption.font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            graph.frame(height: 22)
        }
        .frame(maxWidth: .infinity, minHeight: 92, maxHeight: 92, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.055)))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value). \(captionSpoken)")
        if let open { Button(action: open) { content }.buttonStyle(.plain).focusEffectDisabled() } else { content }
    }
}

/// One line: name, a small bar or graph, and the value.
private struct ThinRow<Graph: View>: View {
    let title: String
    let value: String
    let level: HealthLevel
    let open: (() -> Void)?
    @ViewBuilder var graph: Graph

    var body: some View {
        let row = HStack(spacing: 10) {
            Text(title).font(Typo.small).foregroundStyle(.secondary).frame(width: 52, alignment: .leading)
            graph.frame(maxWidth: .infinity)
            Text(value).font(Typo.small).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                .foregroundStyle(level == .good ? Color.primary : Palette.text(level))
                .frame(minWidth: 150, alignment: .trailing).layoutPriority(1)
        }
        .frame(height: 30).contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value)")
        if let open { Button(action: open) { row }.buttonStyle(.plain).focusEffectDisabled() } else { row }
    }
}

/// 5 min, 1 hr and 24 hr: small text buttons, the chosen one on a soft pill.
private struct RangePicker: View {
    @Binding var range: HistoryRange
    var body: some View {
        HStack(spacing: 2) {
            Spacer()
            ForEach(HistoryRange.allCases) { r in
                Button { range = r } label: {
                    Text(r.rawValue).font(Typo.small).monospacedDigit()
                        .foregroundStyle(r == range ? Color.primary : Color.primary.opacity(0.55))
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(r == range ? 0.1 : 0)))
                }
                .buttonStyle(.plain).focusEffectDisabled()
                .accessibilityLabel("Graph \(r.spoken)").accessibilityAddTraits(r == range ? .isSelected : [])
            }
        }
        .padding(.trailing, 2)
    }
}
