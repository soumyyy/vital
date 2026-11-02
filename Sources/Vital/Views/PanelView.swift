import SwiftUI
import ServiceManagement
import VitalCore

struct PanelView: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        VStack(spacing: 10) {
            if model.snapshot.band == .struggling { StrugglingStrip(model: model) }
            RowsView(model: model)
            TabsView(model: model)
            ScrollView(.vertical, showsIndicators: false) {
                BreakdownView(model: model)
            }
            .frame(maxHeight: .infinity)
            if let p = model.pending { ConfirmBar(model: model, pending: p) }
            else if let t = model.toast { ToastBar(text: t) }
            FooterView(model: model, storage: model.storage)
        }
        .padding(14)
        .frame(width: 340, height: 620)
        .panelBackground()
        .animation(.easeOut(duration: 0.15), value: model.pending?.id)
        .animation(.easeOut(duration: 0.15), value: model.tab)
    }
}

struct StrugglingStrip: View {
    @ObservedObject var model: PanelModel
    var body: some View {
        let hung = model.unresponsiveGroups
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.orange)
                Text("Mac is struggling").font(.system(size: 12, weight: .semibold))
                Spacer()
            }
            Text(cause).font(.system(size: 11)).foregroundStyle(.secondary)
            if !hung.isEmpty {
                Button("Force Quit \(hung.count) not responding") { model.request(.quitAllUnresponsive, hung) }
                    .buttonStyle(PillButton(destructive: true))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.orange.opacity(0.18)))
    }

    private var cause: String {
        let s = model.snapshot
        if s.thermal.state >= .serious { return "The Mac is hot and slowing itself down to cool off." }
        if s.memory?.pressure == .critical { return "Memory is almost full, so the Mac is swapping to disk." }
        if let top = Ranking.sorted(s.groups.filter { !$0.isAggregate }, by: .cpu).first, top.cpuCores > 0.5 {
            return "\(top.name) is using the most CPU."
        }
        return "Heavy load for the last few seconds."
    }
}

struct ConfirmBar: View {
    @ObservedObject var model: PanelModel
    let pending: PendingAction
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(pending.title).font(.system(size: 12, weight: .semibold))
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { model.cancelPending() }.buttonStyle(PillButton())
                Button(pending.kind == .quit ? "Quit" : "Force Quit") { model.confirmPending() }
                    .buttonStyle(PillButton(destructive: pending.kind != .quit))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
    private var detail: String {
        let n = pending.groups.reduce(0) { $0 + $1.processes.count }
        return "\(pending.detail) Affects \(n) process\(n == 1 ? "" : "es")."
    }
}

struct ToastBar: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 11)).frame(maxWidth: .infinity, alignment: .leading).card()
    }
}

struct FooterView: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var storage: StorageStore
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        HStack(spacing: 10) {
            Text("Vital").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            Spacer()
            Button { model.refresh() } label: {
                ZStack {
                    if model.isRefreshing { ProgressView().controlSize(.small).scaleEffect(0.7) }
                    else { Image(systemName: "arrow.clockwise") }
                }
                .frame(width: 18, height: 18).foregroundStyle(.secondary).contentShape(Rectangle())
            }
            .buttonStyle(.plain).focusEffectDisabled()
            .help(model.tab == .storage ? "Refresh and rescan storage" : "Refresh now")
            .accessibilityLabel(model.tab == .storage ? "Refresh and rescan storage" : "Refresh now")
            Menu {
                Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: { setLaunchAtLogin($0) }))
                Divider()
                Button("About Vital") { NSApp.orderFrontStandardAboutPanel(nil) }
                Button("Quit Vital") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis").foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .accessibilityLabel("Vital menu")
        }
    }
    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch { NSLog("Vital: launch at login failed: \(error.localizedDescription)") }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
