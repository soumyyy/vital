import SwiftUI
import VitalCore

struct TabsView: View {
    @ObservedObject var model: PanelModel
    var body: some View {
        HStack(spacing: 4) {
            ForEach(PanelTab.allCases) { tab in
                Button { model.tab = tab } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 11, weight: model.tab == tab ? .semibold : .regular))
                        .frame(maxWidth: .infinity).padding(.vertical, 5)
                        .background(Capsule().fill(model.tab == tab ? Color.primary.opacity(0.16) : .clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .accessibilityAddTraits(model.tab == tab ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(.primary.opacity(0.07)))
    }
}

struct BreakdownView: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        if model.tab == .storage {
            StorageBreakdownView(model: model)
        } else if !model.snapshot.hasProcessData {
            VStack { ProgressView().controlSize(.small); Text("Loading…").font(.system(size: 11)).foregroundStyle(.secondary) }
                .frame(maxWidth: .infinity, minHeight: 80)
        } else {
            let groups = Array(model.ranked.prefix(12))
            if model.tab == .heat { FanCard(model: model) }
            if model.tab == .disk { DiskSummaryCard(model: model) }
            VStack(spacing: 0) {
                ForEach(groups) { g in
                    GroupRow(model: model, group: g)
                    if g.id != groups.last?.id { Divider().opacity(0.4) }
                }
            }
            .card(radius: 14)
        }
    }
}

struct GroupRow: View {
    @ObservedObject var model: PanelModel
    let group: AppGroup

    private var isOpen: Bool { model.expanded.contains(group.id) }
    private var hung: Bool { model.isUnresponsive(group) }
    private var keepsAwake: Bool { group.processes.contains { model.snapshot.sleepBlockers[$0.pid] != nil } }

    var body: some View {
        VStack(spacing: 0) {
            Button { if !group.isAggregate || !group.processes.isEmpty { model.toggle(group) } } label: {
                HStack(spacing: 8) {
                    if group.isAggregate {
                        Image(systemName: "gearshape.2").frame(width: 22, height: 22).foregroundStyle(.secondary)
                    } else {
                        Image(nsImage: model.icon(for: group)).resizable().frame(width: 22, height: 22)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(group.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Text(subtitle).font(.system(size: 10)).foregroundStyle(hung ? Palette.red : (keepsAwake ? Palette.orange : .secondary))
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(value).font(.system(size: 12, weight: .medium)).monospacedDigit()
                        if let detail = valueDetail {
                            Text(detail).font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    if !group.processes.isEmpty {
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary).rotationEffect(.degrees(isOpen ? 90 : 0))
                    }
                }
                .padding(.vertical, 6).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .accessibilityElement(children: .combine)

            if isOpen { expanded }
        }
    }

    private var subtitle: String {
        if hung { return "Not responding" }
        if group.isAggregate { return "Approximate · macOS hides these from apps" }
        if group.isProtected { return "System process · protected" }
        let n = group.processes.count
        let base = n == 1 ? "1 process" : "\(n) processes"
        return keepsAwake ? base + " · keeping Mac awake" : base
    }

    private var value: String {
        switch model.tab {
        case .cpu: return (group.isAggregate ? "≈ " : "") + Format.cpuShare(cores: group.cpuCores, coreCount: coreCount)
        case .memory: return (group.isAggregate ? "≈ " : "") + Format.bytes(group.footprintBytes, base: .binary)
        case .heat: return group.watts.map { String(format: "%.1f W", $0) } ?? "n/a"
        case .disk: return Format.rate(group.diskBytesPerSec)
        case .storage: return ""
        }
    }
    private var coreCount: Int { model.snapshot.cpu?.perCore.count ?? 1 }

    /// Second line: the same load as Activity Monitor would show it (100% = one core).
    private var valueDetail: String? {
        switch model.tab {
        case .cpu: return Format.ofOneCore(group.cpuCores)
        case .heat: return group.wakeupsPerSec >= 1 ? "\(Int(group.wakeupsPerSec.rounded())) wake-ups/s" : nil
        case .disk: return "R \(Format.rate(group.diskReadBytesPerSec)) · W \(Format.rate(group.diskWriteBytesPerSec))"
        default: return nil
        }
    }

    private var expanded: some View {
        VStack(spacing: 4) {
            ForEach(group.processes.prefix(8)) { p in
                HStack {
                    Text(p.name).lineLimit(1)
                    Spacer()
                    if model.tab == .cpu {
                        Text(Format.cpuShare(cores: p.cpuCores, coreCount: coreCount)).monospacedDigit()
                            + Text("  \(Int((p.cpuCores * 100).rounded()))% of a core").foregroundStyle(.tertiary)
                    } else {
                        Text(processValue(p)).monospacedDigit()
                    }
                }
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .padding(.leading, 30)
            }
            if group.processes.count > 8 {
                Text("+ \(group.processes.count - 8) more").font(.system(size: 10)).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 30)
            }
            if model.tab == .disk {
                Text("Written since launch: \(Format.bytes(group.diskWrittenTotal, base: .decimal))")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 30)
            }
            actionBar.padding(.top, 4)
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder private var actionBar: some View {
        if group.isAggregate {
            EmptyView()
        } else if group.isProtected {
            Label("Protected: Vital will not quit this", systemImage: "lock.fill")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 30)
        } else {
            HStack(spacing: 8) {
                Spacer()
                Button("Quit") { model.request(.quit, [group]) }.buttonStyle(PillButton())
                Button("Force Quit") { model.request(.force, [group]) }.buttonStyle(PillButton(destructive: true))
            }
        }
    }

    private func processValue(_ p: ProcessRow) -> String {
        switch model.tab {
        case .cpu: return "\(Format.cpuShare(cores: p.cpuCores, coreCount: coreCount)) · \(Int((p.cpuCores * 100).rounded()))%"
        case .memory: return Format.bytes(p.footprintBytes, base: .binary)
        case .heat: return p.watts.map { String(format: "%.1f W", $0) } ?? "n/a"
        case .disk: return "\(Format.rate(p.diskReadBytesPerSec)) read · \(Format.rate(p.diskWriteBytesPerSec)) write"
        case .storage: return ""
        }
    }
}

struct PillButton: ButtonStyle {
    var destructive = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(Capsule().fill(destructive ? Palette.red.opacity(0.75) : Color.primary.opacity(0.14)))
            .foregroundStyle(destructive ? Color.white : Color.primary)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct StorageBreakdownView: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var store: StorageStore

    init(model: PanelModel) {
        self.model = model
        self.store = model.storage
    }

    var body: some View {
        VStack(spacing: 8) {
            CapacityCard(capacity: store.capacity ?? model.snapshot.storage, store: store)
            if let b = store.breakdown {
                let used = (store.capacity ?? model.snapshot.storage)?.usedBytes ?? 0
                VStack(spacing: 0) {
                    ForEach(ordered(b.categories)) { c in
                        CategoryRow(model: model, category: c)
                        Divider().opacity(0.4)
                    }
                    if b.isComplete {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Other").font(.system(size: 12, weight: .medium))
                                Text("System data, snapshots, swap, unreadable folders")
                                    .font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(Format.bytes(b.otherBytes(usedBytes: used), base: .decimal)).font(.system(size: 12)).monospacedDigit()
                        }
                        .padding(.vertical, 6)
                        .accessibilityElement(children: .combine)
                    }
                }
                .card()
                notes(b)
            }
        }
        .animation(.easeOut(duration: 0.2), value: store.breakdown?.doneCount)
    }

    /// Finished categories by size, then the one being scanned, then those waiting.
    private func ordered(_ cats: [StorageCategory]) -> [StorageCategory] {
        let rank: (ScanStatus) -> Int = { $0 == .done ? 0 : ($0 == .scanning ? 1 : ($0 == .waiting ? 2 : 3)) }
        return cats.enumerated().sorted { a, b in
            let ra = rank(a.element.status), rb = rank(b.element.status)
            if ra != rb { return ra < rb }
            if ra == 0 && a.element.bytes != b.element.bytes { return a.element.bytes > b.element.bytes }
            return a.offset < b.offset
        }.map(\.element)
    }

    @ViewBuilder private func notes(_ b: StorageBreakdown) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if store.fullDiskAccess == false {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Optional: Full Disk Access", systemImage: "lock.fill")
                        .font(.system(size: 11, weight: .medium))
                    Text("Vital works without it. Mail, Messages, Safari and other apps' data count toward Other. Grant access only if you want those measured, then reopen Vital.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open Privacy Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                    }
                    .buttonStyle(PillButton())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
            } else if b.partial && b.isComplete {
                Text("Some system folders are readable only by macOS. They count toward Other.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if b.hasSkipped {
                Text("Documents, Downloads, Photos and similar folders are not opened unless you tap Scan, so macOS does not ask for permission.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Cloud drives (Library/CloudStorage) are skipped: their files are mostly online-only.")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Used / free for the boot volume, available at once, plus the scan status line.
struct CapacityCard: View {
    let capacity: StorageReading?
    @ObservedObject var store: StorageStore

    var body: some View {
        VStack(spacing: 6) {
            if let s = capacity {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Format.bytes(s.usedBytes, base: .decimal)) used").font(.system(size: 12, weight: .semibold))
                    Text("of \(Format.bytes(s.totalBytes, base: .decimal))").font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Format.bytes(s.availableBytes, base: .decimal)) free").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .monospacedDigit()
                UsageBar(fraction: s.usedFraction, color: s.usedFraction < 0.75 ? Palette.green : (s.usedFraction < 0.9 ? Palette.yellow : Palette.red))
            }
            HStack(spacing: 6) {
                if store.scanning {
                    ProgressView().controlSize(.mini)
                    Text("Measuring folders · \(store.breakdown?.doneCount ?? 0) of \(store.breakdown?.scannableCount ?? 0) done")
                } else if let b = store.breakdown, b.isComplete {
                    Text("Folders measured \(ago(b.scannedAt))")
                } else {
                    Text("Folder sizes are measured while this tab is open")
                }
                Spacer()
            }
            .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    private func ago(_ d: Date) -> String {
        let s = Date().timeIntervalSince(d)
        if s < 60 { return "just now" }
        let m = Int(s / 60)
        return m == 1 ? "1 min ago" : "\(m) min ago"
    }
}

struct CategoryRow: View {
    @ObservedObject var model: PanelModel
    let category: StorageCategory

    private var isOpen: Bool { model.expanded.contains("storage:" + category.name) }
    private var expandable: Bool { category.status == .done && !category.top.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                guard expandable else { return }
                let id = "storage:" + category.name
                if isOpen { model.expanded.remove(id) } else { model.expanded.insert(id) }
            } label: {
                HStack(spacing: 6) {
                    Text(category.name).font(.system(size: 12, weight: .medium))
                        .foregroundStyle(category.status == .waiting || category.status == .skipped ? .secondary : .primary)
                    if category.partial && category.status == .done {
                        Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(.tertiary)
                            .help("Some folders here could not be read")
                    }
                    Spacer()
                    value
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .opacity(expandable ? 1 : 0)
                }
                .padding(.vertical, 6).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .accessibilityElement(children: .combine)
            .accessibilityValue(accessibilityValue)
            if isOpen {
                ForEach(category.top) { f in
                    HStack {
                        Text((f.path as NSString).lastPathComponent).lineLimit(1)
                        Spacer()
                        Text(Format.bytes(f.bytes, base: .decimal)).monospacedDigit()
                        Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: f.path)]) } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .buttonStyle(.plain).help("Reveal in Finder").accessibilityLabel("Reveal \((f.path as NSString).lastPathComponent) in Finder")
                    }
                    .font(.system(size: 11)).foregroundStyle(.secondary).padding(.leading, 12).padding(.bottom, 4)
                }
            }
        }
    }

    @ViewBuilder private var value: some View {
        switch category.status {
        case .waiting:
            Text("Waiting").font(.system(size: 11)).foregroundStyle(.tertiary)
        case .scanning:
            HStack(spacing: 5) {
                ProgressView().controlSize(.mini)
                Text(Format.bytes(category.bytes, base: .decimal) + "…").font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
            }
        case .skipped:
            Button("Scan") { model.storage.allow(category.name, busy: model.snapshot.band != .calm) }
                .buttonStyle(PillButton())
                .help("macOS will ask once for permission to read this folder")
        case .done:
            if category.bytes == 0 && category.partial {
                Text("Not readable").font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                Text(Format.bytes(category.bytes, base: .decimal)).font(.system(size: 12)).monospacedDigit()
            }
        }
    }

    private var accessibilityValue: String {
        switch category.status {
        case .waiting: return "waiting"
        case .scanning: return "measuring, \(Format.bytes(category.bytes, base: .decimal)) so far"
        case .skipped: return "not scanned, private folder. Choose Scan to include it"
        case .done: return Format.bytes(category.bytes, base: .decimal) + (category.partial ? ", partial" : "")
        }
    }
}

/// Disk activity at a glance: what the visible apps read and write, and how much the Mac is reading
/// back from disk because memory ran short (page-ins).
struct DiskSummaryCard: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        let snap = model.snapshot
        let apps = snap.groups.filter { !$0.isAggregate }
        let read = apps.reduce(0) { $0 + $1.diskReadBytesPerSec }
        let write = apps.reduce(0) { $0 + $1.diskWriteBytesPerSec }
        let pageIn = snap.pageInBytesPerSec
        let swapUsed = snap.memory?.swapUsedBytes ?? 0
        let thrashing = pageIn > 20_000_000 && swapUsed > 500_000_000
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reading").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(Format.rate(read)).font(.system(size: 15, weight: .semibold)).monospacedDigit()
                }
                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Writing").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(Format.rate(write)).font(.system(size: 15, weight: .semibold)).monospacedDigit()
                }
                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    Text("From memory swap").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(Format.rate(pageIn)).font(.system(size: 15, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(thrashing ? Palette.red : .primary)
                }
            }
            if thrashing {
                Label("The Mac is short of memory and is reading it back from disk. Quit a heavy app to speed things up.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11)).foregroundStyle(Palette.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Apps you can see. System services are not included.")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .combine)
    }
}
