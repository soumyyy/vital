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

/// One titled group of rows inside a details card. Groups are separated by a hairline.
struct DetailGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.5)
                .foregroundStyle(.secondary).padding(.bottom, 2)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A details card: its groups stacked with a hairline between them.
struct DetailsCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }.card()
    }
}

extension View {
    /// Hairline above a group (everything but the first).
    func divided() -> some View {
        VStack(alignment: .leading, spacing: 10) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1); self }
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
        DetailsCard {
            if let c = model.snapshot.cpu {
                DetailGroup(title: "Load") {
                    DetailRow(label: "In use", value: Format.percent(c.total))
                    if model.history.count > 1 {
                        Sparkline(values: model.history, color: Health.cpu(c.total) == .good ? Color.primary.opacity(0.5) : Palette.color(Health.cpu(c.total)))
                            .frame(height: 30).padding(.top, 4)
                    }
                }
                if c.performance != nil || c.efficiency != nil {
                    DetailGroup(title: "Cores") {
                        if let p = c.performance { DetailRow(label: "Performance", value: Format.percent(p)) }
                        if let e = c.efficiency { DetailRow(label: "Efficiency", value: Format.percent(e)) }
                    }.divided()
                }
                Note("Apps show their share of the whole CPU. Hover a process for the Activity Monitor figure.")
            } else {
                DetailRow(label: "CPU", value: "n/a")
            }
        }
    }
}

private struct MemoryDetails: View {
    let snapshot: Snapshot
    var body: some View {
        DetailsCard {
            if let m = snapshot.memory {
                let level = Health.memory(m.pressure)
                let thrashing = Health.isThrashing(pageInBytesPerSec: snapshot.pageInBytesPerSec, swapUsedBytes: m.swapUsedBytes)
                DetailGroup(title: "Memory") {
                    DetailRow(label: "In use", value: "\(Format.bytes(m.usedBytes, base: .binary)) of \(Format.bytes(m.totalBytes, base: .binary))")
                    DetailRow(label: "Pressure", value: pressureWord(m.pressure), color: Palette.text(level))
                }
                DetailGroup(title: "Swap") {
                    DetailRow(label: "Used", value: m.swapUsedBytes == 0 ? "None" : Format.bytes(m.swapUsedBytes, base: .binary))
                    DetailRow(label: "Read back from disk", value: Format.rate(snapshot.pageInBytesPerSec), color: thrashing ? Palette.red : .primary)
                }.divided()
                if thrashing {
                    Note("The Mac is short of memory and is reading it back from disk. Quit a heavy app to speed things up.", color: Palette.orange)
                }
            } else {
                DetailRow(label: "Memory", value: "n/a")
            }
        }
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
            DetailsCard {
                if let s = store.capacity ?? snap.storage {
                    DetailGroup(title: "Capacity") {
                        DetailRow(label: "In use", value: "\(Format.bytes(s.usedBytes, base: .decimal)) of \(Format.bytes(s.totalBytes, base: .decimal))")
                        DetailRow(label: "Free", value: Format.bytes(s.availableBytes, base: .decimal))
                    }
                }
                DetailGroup(title: "Disk activity") {
                    DetailRow(label: "Reading", value: Format.rate(apps.reduce(0) { $0 + $1.diskReadBytesPerSec }))
                    DetailRow(label: "Writing", value: Format.rate(apps.reduce(0) { $0 + $1.diskWriteBytesPerSec }))
                }.divided()
                if !busiest.isEmpty {
                    DetailGroup(title: "Busiest apps") {
                        ForEach(Array(busiest)) { g in
                            HStack(spacing: 6) {
                                Image(nsImage: model.icon(for: g)).resizable().frame(width: 14, height: 14)
                                Text(g.name).lineLimit(1)
                                Spacer()
                                Text("\(Format.rate(g.diskReadBytesPerSec)) read · \(Format.rate(g.diskWriteBytesPerSec)) written")
                                    .foregroundStyle(.secondary).monospacedDigit()
                            }
                            .font(Typo.small).padding(.vertical, 2)
                            .help("Written since it started: \(Format.bytes(g.diskWrittenTotal, base: .decimal))")
                        }
                    }.divided()
                }
                Note("Disk activity counts apps you can see. System services are not included.")
            }
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
        DetailsCard {
            DetailGroup(title: "Temperature") {
                DetailRow(label: "macOS thermal state", value: VitalTiles.word(t.state), color: Palette.text(Health.heat(t.state)))
                if t.cpuCelsius == nil && t.gpuCelsius == nil { DetailRow(label: "Sensors", value: "n/a") }
                if let c = t.cpuCelsius { DetailRow(label: "CPU", value: "\(Int(c.rounded())) °C") }
                if let g = t.gpuCelsius { DetailRow(label: "GPU", value: "\(Int(g.rounded())) °C") }
            }
            if let b = snap.battery { DetailGroup(title: "Battery") { battery(b) }.divided() }
            if let n = snap.network {
                DetailGroup(title: "Network") {
                    DetailRow(label: "Download", value: Format.rate(n.downBytesPerSec))
                    DetailRow(label: "Upload", value: Format.rate(n.upBytesPerSec))
                }.divided()
            }
            let awake = awakeNames
            if !awake.isEmpty {
                DetailGroup(title: "Keeping your Mac awake") {
                    ForEach(awake, id: \.self) { Text($0).font(Typo.small).foregroundStyle(Palette.orange).padding(.vertical, 2) }
                }.divided()
            }
        }
    }

    @ViewBuilder private func battery(_ b: BatteryReading) -> some View {
        let state = b.isCharging ? "charging" : (b.onPower ? "plugged in" : "on battery")
        DetailRow(label: "Level", value: "\(b.percent)%, \(state)",
                  color: !b.onPower && b.percent <= 20 ? Palette.red : .primary)
        if let w = b.watts, !b.onPower || b.isCharging { DetailRow(label: b.isCharging ? "Charging at" : "Drawing", value: String(format: "%.1f W", w)) }
        if let m = b.minutesRemaining { DetailRow(label: b.isCharging ? "Until full" : "Time left", value: Format.duration(minutes: m)) }
        if let h = b.healthFraction {
            DetailRow(label: "Health", value: Format.percent(h) + (b.cycleCount.map { ", \($0) cycles" } ?? ""))
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
