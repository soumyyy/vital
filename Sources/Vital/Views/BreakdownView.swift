import SwiftUI
import VitalCore

/// Small heading above a list or a details card.
struct SectionLabel<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(spacing: 6) {
            Text(title).font(Typo.smallBold).foregroundStyle(.secondary)
            Spacer()
            trailing.font(Typo.small).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
    }
}

extension SectionLabel where Trailing == EmptyView {
    init(_ title: String) { self.title = title; self.trailing = EmptyView() }
}

/// The apps using the most of the selected vital (folders, for Storage).
struct BreakdownView: View {
    @ObservedObject var model: PanelModel
    static let shortCount = 6, longCount = 12

    var body: some View {
        if model.tab == .storage {
            StorageBreakdownView(model: model)
        } else if !model.snapshot.hasProcessData {
            // Same height as the list it stands in for, so the panel does not jump when apps arrive.
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(title)
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Loading apps…").font(Typo.small).foregroundStyle(.secondary) }
                    .frame(maxWidth: .infinity).frame(height: CGFloat(Self.shortCount) * 32).card()
            }
        } else {
            // On Heat, rows that round to 0.0 W say nothing.
            let all = model.tab == .heat ? model.ranked.filter { ($0.watts ?? 0) >= 0.05 } : model.ranked
            let groups = Array(all.prefix(model.showAll ? Self.longCount : Self.shortCount))
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(title)
                VStack(spacing: 0) {
                    if groups.isEmpty {
                        Text("No app is drawing noticeable power.").font(Typo.small).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                    }
                    ForEach(groups) { g in GroupRow(model: model, group: g) }
                    if all.count > Self.shortCount {
                        Button(model.showAll ? "Show fewer" : "Show more") { model.showAll.toggle() }
                            .buttonStyle(.plain).focusEffectDisabled()
                            .font(Typo.small).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 30).padding(.vertical, 6)
                    }
                }
                .card()
            }
        }
    }

    private var title: String {
        switch model.tab {
        case .cpu: return "Using the most CPU"
        case .memory: return "Using the most memory"
        case .heat: return "Using the most power"
        case .storage: return "Using the most space"
        }
    }
}

struct GroupRow: View {
    @ObservedObject var model: PanelModel
    let group: AppGroup

    private var isOpen: Bool { model.expanded.contains(group.id) }
    private var hung: Bool { model.isUnresponsive(group) }
    private var expandable: Bool { !group.processes.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            Button { if expandable { model.toggle(group) } } label: {
                HStack(spacing: 10) {
                    if group.isAggregate {
                        Image(systemName: "gearshape.2").font(.system(size: 13)).frame(width: 20, height: 20).foregroundStyle(Color.primary.opacity(0.55))
                    } else {
                        Image(nsImage: model.icon(for: group)).resizable().frame(width: 20, height: 20)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(group.name).font(Typo.mediumBold).lineLimit(1)
                            .foregroundStyle(group.isAggregate ? .secondary : .primary)
                        if hung { Text("Not responding").font(Typo.small).foregroundStyle(Palette.red) }
                    }
                    Spacer(minLength: 4)
                    Text(value).font(Typo.medium).monospacedDigit()
                        .foregroundStyle(group.isAggregate ? .secondary : .primary)
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Palette.faint).rotationEffect(.degrees(isOpen ? 90 : 0))
                        .opacity(expandable ? 1 : 0)
                }
                .padding(.vertical, 6).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .help(group.isAggregate ? "Approximate: macOS does not let apps read these processes exactly" : "")
            .accessibilityElement(children: .combine)
            .accessibilityHint(expandable ? (isOpen ? "Hides processes" : "Shows processes and Quit") : "")

            if isOpen { expanded }
        }
    }

    private var coreCount: Int { model.snapshot.cpu?.perCore.count ?? 1 }

    private var value: String {
        let approx = group.isAggregate ? "≈ " : ""
        switch model.tab {
        case .cpu: return approx + Format.cpuShare(cores: group.cpuCores, coreCount: coreCount)
        case .memory: return approx + Format.bytes(group.footprintBytes, base: .binary)
        case .heat: return group.watts.map { String(format: "%.1f W", $0) } ?? "n/a"
        case .storage: return ""
        }
    }

    /// Process list, power-user extras for this vital, then Quit / Force Quit.
    private var expanded: some View {
        VStack(alignment: .leading, spacing: 4) {
            let kinds = ProcessKind.merge(group.processes, by: model.tab.metric)
            ForEach(kinds.prefix(6)) { k in
                HStack(spacing: 6) {
                    Text(k.name).lineLimit(1)
                    if k.count > 1 { Text("×\(k.count)").foregroundStyle(.tertiary) }
                    Spacer()
                    processValue(k)
                }
            }
            if kinds.count > 6 {
                Text("+ \(kinds.count - 6) more").foregroundStyle(.tertiary)
            }
            if model.tab == .heat {
                if group.wakeupsPerSec >= 1 {
                    Text("Wakes the CPU \(Int(group.wakeupsPerSec.rounded())) times a second").foregroundStyle(.tertiary)
                }
                if group.processes.contains(where: { model.snapshot.sleepBlockers[$0.pid] != nil }) {
                    Label("Keeping your Mac awake", systemImage: "moon.zzz.fill").foregroundStyle(Palette.orange)
                }
            }
            actionBar.padding(.top, 4)
        }
        .font(Typo.small).foregroundStyle(.secondary)
        .padding(.leading, 30).padding(.bottom, 8)
    }

    @ViewBuilder private func processValue(_ k: ProcessKind) -> some View {
        switch model.tab {
        case .cpu:
            Text(Format.cpuShare(cores: k.cpuCores, coreCount: coreCount)).monospacedDigit()
                .help("\(Format.ofOneCore(k.cpuCores)), as Activity Monitor shows it")
        case .memory: Text(Format.bytes(k.footprintBytes, base: .binary)).monospacedDigit()
        case .heat: Text(k.watts.map { String(format: "%.1f W", $0) } ?? "n/a").monospacedDigit()
        case .storage: EmptyView()
        }
    }

    @ViewBuilder private var actionBar: some View {
        if group.isAggregate {
            EmptyView()
        } else if group.isProtected {
            Label("Protected: Vital will not quit this", systemImage: "lock.fill")
        } else {
            HStack(spacing: 8) {
                Spacer()
                Button("Quit") { model.request(.quit, [group]) }.buttonStyle(PillButton())
                Button("Force Quit") { model.request(.force, [group]) }.buttonStyle(PillButton(destructive: true))
            }
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
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(title: "Using the most space") { ScanProgress(store: store) }
            if let b = store.breakdown {
                let used = (store.capacity ?? model.snapshot.storage)?.usedBytes ?? 0
                VStack(spacing: 0) {
                    ForEach(ordered(b.categories)) { c in CategoryRow(model: model, category: c) }
                    if b.isComplete {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Other").font(Typo.mediumBold).foregroundStyle(.secondary)
                            Spacer()
                            Text(Format.bytes(b.otherBytes(usedBytes: used), base: .decimal)).font(Typo.medium).monospacedDigit()
                                .foregroundStyle(.secondary)
                            Color.clear.frame(width: 9, height: 1)     // lines up with the chevrons above
                        }
                        .padding(.vertical, 6)
                        .help("System data, snapshots, swap and folders Vital cannot read")
                        .accessibilityElement(children: .combine)
                    }
                }
                .card()
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
}

/// Scan progress, or when the folders were last measured.
struct ScanProgress: View {
    @ObservedObject var store: StorageStore
    var body: some View {
        HStack(spacing: 5) {
            if store.scanning {
                ProgressView().controlSize(.mini)
                Text("Measuring \(store.breakdown?.doneCount ?? 0) of \(store.breakdown?.scannableCount ?? 0)")
            } else if let b = store.breakdown, b.isComplete {
                Text("Measured \(ago(b.scannedAt))")
            }
        }
        .monospacedDigit()
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
                    Text(category.name).font(Typo.mediumBold)
                        .foregroundStyle(category.status == .waiting || category.status == .skipped ? .secondary : .primary)
                    if category.partial && category.status == .done {
                        Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(Palette.faint)
                            .help("Some folders here could not be read")
                    }
                    Spacer()
                    value
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(Palette.faint)
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
                    .font(Typo.small).foregroundStyle(.secondary).padding(.leading, 12).padding(.bottom, 4)
                }
            }
        }
    }

    @ViewBuilder private var value: some View {
        switch category.status {
        case .waiting:
            Text("Waiting").font(Typo.small).foregroundStyle(.tertiary)
        case .scanning:
            HStack(spacing: 5) {
                ProgressView().controlSize(.mini)
                Text(Format.bytes(category.bytes, base: .decimal) + "…").font(Typo.medium).foregroundStyle(.secondary).monospacedDigit()
            }
        case .skipped:
            Button("Scan") { model.storage.allow(category.name, busy: model.snapshot.band != .calm) }
                .buttonStyle(PillButton())
                .help("macOS will ask once for permission to read this folder")
        case .done:
            if category.bytes == 0 && category.partial {
                Text("Not readable").font(Typo.small).foregroundStyle(.secondary)
            } else {
                Text(Format.bytes(category.bytes, base: .decimal)).font(Typo.medium).monospacedDigit()
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

/// Processes of one app merged by name ("Browser Helper (Renderer) ×24"), largest first.
struct ProcessKind: Identifiable {
    var name: String
    var count: Int
    var cpuCores: Double
    var footprintBytes: UInt64
    var watts: Double?
    var id: String { name }

    static func merge(_ rows: [ProcessRow], by metric: RankMetric) -> [ProcessKind] {
        var byName: [String: ProcessKind] = [:]
        var order: [String] = []
        for r in rows {
            if var k = byName[r.name] {
                k.count += 1; k.cpuCores += r.cpuCores; k.footprintBytes += r.footprintBytes
                if let w = r.watts { k.watts = (k.watts ?? 0) + w }
                byName[r.name] = k
            } else {
                byName[r.name] = ProcessKind(name: r.name, count: 1, cpuCores: r.cpuCores, footprintBytes: r.footprintBytes, watts: r.watts)
                order.append(r.name)
            }
        }
        func value(_ k: ProcessKind) -> Double {
            switch metric {
            case .memory: return Double(k.footprintBytes)
            case .power: return k.watts ?? 0
            default: return k.cpuCores
            }
        }
        return order.compactMap { byName[$0] }.sorted { value($0) > value($1) }
    }
}
