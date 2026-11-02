import SwiftUI
import VitalCore

/// Power-user detail for the selected vital, closed by default.
struct DetailsSection: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { model.showDetails.toggle() } label: {
                HStack(spacing: 4) {
                    Text("Details")
                    Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Palette.faint)
                        .rotationEffect(.degrees(model.showDetails ? 90 : 0))
                }
                .font(Typo.smallBold).foregroundStyle(Color.secondary)
                .padding(.horizontal, 4).contentShape(Rectangle())
            }
            .buttonStyle(.plain).focusEffectDisabled()
            .accessibilityLabel(model.showDetails ? "Hide \(model.tab.rawValue) details" : "Show \(model.tab.rawValue) details")

            if model.showDetails {
                switch model.tab {
                case .cpu: CPUDetails(model: model)
                case .memory: MemoryDetails(snapshot: model.snapshot)
                case .storage: StorageDetails(model: model, store: model.storage)
                case .heat: HeatDetails(model: model)
                }
            }
        }
    }
}

/// Label on the left, value on the right.
struct DetailRow: View {
    let label: String
    let value: String
    var color: Color = .primary
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value).foregroundStyle(color).monospacedDigit().multilineTextAlignment(.trailing)
        }
        .font(Typo.small)
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// Explanatory text under details rows.
struct Note: View {
    let text: String
    var color: Color = .secondary
    init(_ text: String, color: Color = .secondary) { self.text = text; self.color = color }
    var body: some View {
        Text(text).font(Typo.small).foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CPUDetails: View {
    @ObservedObject var model: PanelModel
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let c = model.snapshot.cpu {
                if model.history.count > 1 {
                    Sparkline(values: model.history, color: Health.cpu(c.total) == .good ? Color.primary.opacity(0.5) : Palette.color(Health.cpu(c.total)))
                        .frame(height: 30).padding(.vertical, 4)
                }
                if let p = c.performance { DetailRow(label: "Performance cores", value: Format.percent(p)) }
                if let e = c.efficiency { DetailRow(label: "Efficiency cores", value: Format.percent(e)) }
                Note("Apps show their share of the whole CPU. Hover a process for the Activity Monitor figure.")
                    .padding(.top, 4)
            } else {
                DetailRow(label: "CPU", value: "n/a")
            }
        }
        .card()
    }
}

private struct MemoryDetails: View {
    let snapshot: Snapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let m = snapshot.memory {
                let level = Health.memory(m.pressure)
                let thrashing = Health.isThrashing(pageInBytesPerSec: snapshot.pageInBytesPerSec, swapUsedBytes: m.swapUsedBytes)
                DetailRow(label: "In use", value: "\(Format.bytes(m.usedBytes, base: .binary)) of \(Format.bytes(m.totalBytes, base: .binary))")
                DetailRow(label: "Pressure", value: pressureWord(m.pressure), color: Palette.text(level))
                DetailRow(label: "Swap", value: m.swapUsedBytes == 0 ? "None" : Format.bytes(m.swapUsedBytes, base: .binary))
                DetailRow(label: "Read back from disk", value: Format.rate(snapshot.pageInBytesPerSec), color: thrashing ? Palette.red : .primary)
                if thrashing {
                    Note("The Mac is short of memory and is reading it back from disk. Quit a heavy app to speed things up.",
                         color: Palette.orange).padding(.top, 4)
                }
            } else {
                DetailRow(label: "Memory", value: "n/a")
            }
        }
        .card()
    }

    private func pressureWord(_ p: MemoryPressure) -> String {
        switch p { case .normal: return "Normal"; case .elevated: return "Elevated"; case .critical: return "Critical" }
    }
}

private struct StorageDetails: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var store: StorageStore

    var body: some View {
        let snap = model.snapshot
        let apps = snap.groups.filter { !$0.isAggregate }
        let busiest = Ranking.sorted(apps, by: .disk).filter { $0.diskBytesPerSec >= 1000 }.prefix(3)
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                if let s = store.capacity ?? snap.storage {
                    DetailRow(label: "In use", value: "\(Format.bytes(s.usedBytes, base: .decimal)) of \(Format.bytes(s.totalBytes, base: .decimal))")
                    DetailRow(label: "Free", value: Format.bytes(s.availableBytes, base: .decimal))
                }
                DetailRow(label: "Reading", value: Format.rate(apps.reduce(0) { $0 + $1.diskReadBytesPerSec }))
                DetailRow(label: "Writing", value: Format.rate(apps.reduce(0) { $0 + $1.diskWriteBytesPerSec }))
                ForEach(Array(busiest)) { g in
                    HStack(spacing: 6) {
                        Image(nsImage: model.icon(for: g)).resizable().frame(width: 14, height: 14)
                        Text(g.name).lineLimit(1)
                        Spacer()
                        Text("\(Format.rate(g.diskReadBytesPerSec)) read · \(Format.rate(g.diskWriteBytesPerSec)) written")
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                    .font(Typo.small).padding(.leading, 8)
                    .help("Written since it started: \(Format.bytes(g.diskWrittenTotal, base: .decimal))")
                }
                Note("Disk activity counts apps you can see. System services are not included.").padding(.top, 2)
            }
            .card()
            notes
        }
    }

    @ViewBuilder private var notes: some View {
        VStack(alignment: .leading, spacing: 6) {
            if store.fullDiskAccess == false {
                Note("Optional: Full Disk Access. Without it, Mail, Messages, Safari and other apps' data count toward Other.")
                Button("Open Privacy Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                }
                .buttonStyle(PillButton())
            } else if let b = store.breakdown, b.partial && b.isComplete {
                Note("Some system folders are readable only by macOS. They count toward Other.")
            }
            if store.breakdown?.hasSkipped == true {
                Note("Documents, Downloads, Photos and similar folders are opened only when you tap Scan, so macOS does not ask for permission.")
            }
            Note("Cloud drives are skipped: their files are mostly online-only.")
        }
        .padding(.horizontal, 4)
    }
}

private struct HeatDetails: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        let snap = model.snapshot
        let t = snap.thermal
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                DetailRow(label: "macOS thermal state", value: VitalTiles.word(t.state), color: Palette.text(Health.heat(t.state)))
                if t.cpuCelsius == nil && t.gpuCelsius == nil {
                    DetailRow(label: "Temperatures", value: "n/a")
                }
                if let c = t.cpuCelsius { DetailRow(label: "CPU temperature", value: "\(Int(c.rounded())) °C") }
                if let g = t.gpuCelsius { DetailRow(label: "GPU temperature", value: "\(Int(g.rounded())) °C") }
                if let b = snap.battery { battery(b) }
                if let n = snap.network {
                    DetailRow(label: "Network", value: "↓ \(Format.rate(n.downBytesPerSec))  ↑ \(Format.rate(n.upBytesPerSec))")
                }
                let awake = awakeNames
                if !awake.isEmpty {
                    DetailRow(label: "Keeping Mac awake", value: awake.joined(separator: ", "), color: Palette.orange)
                }
            }
            .card()
            FanCard(model: model)
        }
    }

    @ViewBuilder private func battery(_ b: BatteryReading) -> some View {
        let state = b.isCharging ? "charging" : (b.onPower ? "plugged in" : "on battery")
        DetailRow(label: "Battery", value: "\(b.percent)%, \(state)",
                  color: !b.onPower && b.percent <= 20 ? Palette.red : .primary)
        if let w = b.watts, !b.onPower || b.isCharging { DetailRow(label: b.isCharging ? "Charging at" : "Drawing", value: String(format: "%.1f W", w)) }
        if let m = b.minutesRemaining { DetailRow(label: b.isCharging ? "Until full" : "Time left", value: Format.duration(minutes: m)) }
        if let h = b.healthFraction {
            DetailRow(label: "Battery health", value: Format.percent(h) + (b.cycleCount.map { ", \($0) cycles" } ?? ""))
        }
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
}
