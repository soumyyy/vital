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
            VStack { ProgressView().controlSize(.small); Text("Sampling…").font(.system(size: 11)).foregroundStyle(.secondary) }
                .frame(maxWidth: .infinity, minHeight: 80)
        } else {
            let groups = Array(model.ranked.prefix(12))
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
                        Text(subtitle).font(.system(size: 10)).foregroundStyle(hung ? Palette.red : .secondary)
                    }
                    Spacer(minLength: 4)
                    Text(value).font(.system(size: 12)).monospacedDigit()
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
        return n == 1 ? "1 process" : "\(n) processes"
    }

    private var value: String {
        switch model.tab {
        case .cpu: return group.isAggregate ? "≈ \(percent(group.cpuCores))" : percent(group.cpuCores)
        case .memory: return (group.isAggregate ? "≈ " : "") + Format.bytes(group.footprintBytes, base: .binary)
        case .heat: return group.watts.map { String(format: "%.1f W", $0) } ?? "n/a"
        case .storage: return ""
        }
    }
    private func percent(_ cores: Double) -> String { "\(Int((cores * 100).rounded()))%" }

    private var expanded: some View {
        VStack(spacing: 4) {
            ForEach(group.processes.prefix(8)) { p in
                HStack {
                    Text(p.name).lineLimit(1)
                    Spacer()
                    Text(processValue(p)).monospacedDigit()
                }
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .padding(.leading, 30)
            }
            if group.processes.count > 8 {
                Text("+ \(group.processes.count - 8) more").font(.system(size: 10)).foregroundStyle(.tertiary)
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
        case .cpu: return percent(p.cpuCores)
        case .memory: return Format.bytes(p.footprintBytes, base: .binary)
        case .heat: return p.watts.map { String(format: "%.1f W", $0) } ?? "n/a"
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

    var body: some View {
        VStack(spacing: 8) {
            if let b = model.breakdown {
                let used = model.snapshot.storage?.usedBytes ?? 0
                let cats = b.categories.sorted { $0.bytes > $1.bytes }
                VStack(spacing: 0) {
                    ForEach(cats) { c in
                        CategoryRow(model: model, category: c, used: used)
                        Divider().opacity(0.4)
                    }
                    if b.isComplete {
                        let other = b.otherBytes(usedBytes: used)
                        HStack {
                            Text("Other").font(.system(size: 12, weight: .medium))
                            Text("snapshots, purgeable, system data").font(.system(size: 10)).foregroundStyle(.secondary)
                            Spacer()
                            Text(Format.bytes(other, base: .decimal)).font(.system(size: 12)).monospacedDigit()
                        }
                        .padding(.vertical, 6)
                    }
                }
                .card()
                if model.scanning {
                    HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Scanning…").font(.system(size: 11)).foregroundStyle(.secondary) }
                }
                if b.partial {
                    Button {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                    } label: {
                        Text("Partial: some folders are unreadable. Grant Full Disk Access to see everything.")
                            .font(.system(size: 10)).multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain).foregroundStyle(Palette.yellow)
                }
            } else {
                VStack(spacing: 6) { ProgressView().controlSize(.small); Text("Scanning…").font(.system(size: 11)).foregroundStyle(.secondary) }
                    .frame(maxWidth: .infinity, minHeight: 80)
            }
        }
    }
}

struct CategoryRow: View {
    @ObservedObject var model: PanelModel
    let category: StorageCategory
    let used: UInt64

    private var isOpen: Bool { model.expanded.contains("storage:" + category.name) }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                let id = "storage:" + category.name
                if isOpen { model.expanded.remove(id) } else { model.expanded.insert(id) }
            } label: {
                HStack {
                    Text(category.name).font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text(Format.bytes(category.bytes, base: .decimal)).font(.system(size: 12)).monospacedDigit()
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .padding(.vertical, 6).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isOpen {
                ForEach(category.top) { f in
                    HStack {
                        Text((f.path as NSString).lastPathComponent).lineLimit(1)
                        Spacer()
                        Text(Format.bytes(f.bytes, base: .decimal)).monospacedDigit()
                        Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: f.path)]) } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .buttonStyle(.plain).help("Reveal in Finder")
                    }
                    .font(.system(size: 11)).foregroundStyle(.secondary).padding(.leading, 12).padding(.bottom, 4)
                }
            }
        }
    }
}
