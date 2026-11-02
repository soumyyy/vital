import SwiftUI
import ServiceManagement
import VitalCore

struct PanelView: View {
    @ObservedObject var model: PanelModel
    @State private var contentHeight: CGFloat = 0
    @State private var headerHeight: CGFloat = 0
    @State private var footerHeight: CGFloat = 0

    private var hasHeader: Bool { !model.overview || !model.unresponsiveGroups.isEmpty }
    private var panelHeight: CGFloat {
        if !model.overview { return min(model.minHeight, model.maxHeight) }
        let chrome = headerHeight + footerHeight + 28 + (hasHeader ? 24 : 12)
        return min(model.maxHeight, max(model.floorHeight, contentHeight + chrome))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if hasHeader {
                VStack(spacing: 12) {
                    if !model.overview { VitalTiles(model: model) }
                    if !model.unresponsiveGroups.isEmpty { NotRespondingStrip(model: model) }
                }
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { g in Color.clear.preference(key: PanelSizes.self, value: PanelSizes(header: g.size.height)) })
            }
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 12) {
                    if model.overview {
                        OverviewView(model: model)
                    } else {
                        if let status = model.status { StatusLine(model: model, status: status) }
                        if model.tab == .heat { FanCard(model: model) }
                        BreakdownView(model: model)
                        DetailsSection(model: model)
                    }
                }
                .background(GeometryReader { g in Color.clear.preference(key: PanelSizes.self, value: PanelSizes(content: g.size.height)) })
            }
            .frame(maxHeight: .infinity)
            VStack(spacing: 12) {
                if let p = model.pending { ConfirmBar(model: model, pending: p) }
                else if let t = model.toast { ToastBar(text: t) }
                FloatingPill(model: model, storage: model.storage).frame(maxWidth: .infinity, alignment: .trailing)
            }
            .fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { g in Color.clear.preference(key: PanelSizes.self, value: PanelSizes(footer: g.size.height)) })
        }
        .padding(.horizontal, 14).padding(.top, 16).padding(.bottom, 12)
        .frame(width: 340, height: panelHeight)
        .onPreferenceChange(PanelSizes.self) { s in
            contentHeight = s.content
            headerHeight = s.header
            footerHeight = s.footer
            model.onHeight?(panelHeight)
        }
        .panelBackground()
        .onChange(of: panelHeight, initial: true) { _, height in model.onHeight?(height) }
        .animation(.easeOut(duration: 0.15), value: model.pending?.id)
    }
}

/// Measure intrinsic sections independently; never derive chrome from the resized window.
struct PanelSizes: PreferenceKey, Equatable {
    var content: CGFloat = 0, header: CGFloat = 0, footer: CGFloat = 0
    static let defaultValue = PanelSizes()
    static func reduce(value: inout PanelSizes, nextValue: () -> PanelSizes) {
        let n = nextValue()
        value = PanelSizes(content: max(value.content, n.content), header: max(value.header, n.header), footer: max(value.footer, n.footer))
    }
}

/// What is wrong with the selected vital, with the one app that would fix it. Appears only when something is.
struct StatusLine: View {
    @ObservedObject var model: PanelModel
    let status: Headline

    var body: some View {
        let culprit = status.culpritID.flatMap(model.group(id:))
        let color = Palette.color(status.level)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: status.level == .critical ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(color).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.title).font(Typo.mediumBold)
                    if let d = status.detail {
                        Text(d).font(Typo.small).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            if let g = culprit {
                Button("Quit \(g.name)…") { model.request(.quit, [g]) }
                    .buttonStyle(PillButton()).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(color.opacity(0.13)))
        .accessibilityElement(children: .contain)
    }
}

/// Apps that have stopped responding. This is the one thing that interrupts whatever tab is open.
struct NotRespondingStrip: View {
    @ObservedObject var model: PanelModel
    var body: some View {
        let hung = model.unresponsiveGroups
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.red).accessibilityHidden(true)
            Text(hung.count == 1 ? "\(hung[0].name) is not responding" : "\(hung.count) apps are not responding")
                .font(Typo.mediumBold).lineLimit(1)
            Spacer(minLength: 4)
            Button("Force Quit") { model.request(.quitAllUnresponsive, hung) }.buttonStyle(PillButton(destructive: true))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.red.opacity(0.14)))
        .accessibilityElement(children: .contain)
    }
}

struct ConfirmBar: View {
    @ObservedObject var model: PanelModel
    let pending: PendingAction
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(pending.title).font(Typo.mediumBold)
            Text(detail).font(Typo.small).foregroundStyle(.secondary)
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
        Text(text).font(Typo.small).frame(maxWidth: .infinity, alignment: .leading).card()
    }
}

/// Glass capsule at the foot of the panel: refresh and the three-dot menu.
struct FloatingPill: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var storage: StorageStore
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        HStack(spacing: 14) {
            Button { model.refresh() } label: {
                ZStack {
                    if model.isRefreshing { ProgressView().controlSize(.small).scaleEffect(0.7) }
                    else { Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .medium)) }
                }
                .frame(width: 20, height: 20).contentShape(Rectangle())
            }
            .buttonStyle(.plain).focusEffectDisabled()
            .help(model.tab == .storage ? "Refresh and rescan storage" : "Refresh now")
            .accessibilityLabel(model.tab == .storage ? "Refresh and rescan storage" : "Refresh now")

            Button { model.toggleOverview() } label: {
                Image(systemName: model.overview ? "square.grid.2x2.fill" : "square.grid.2x2").font(.system(size: 12, weight: .medium))
                    .frame(width: 20, height: 20).contentShape(Rectangle())
            }
            .buttonStyle(.plain).focusEffectDisabled()
            .help(model.overview ? "Back to apps" : "Overview of everything")
            .accessibilityLabel(model.overview ? "Back to apps" : "Overview")

            Menu {
                Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: { setLaunchAtLogin($0) }))
                Divider()
                Button("About Vital") { AboutPanel.show() }
                Button("Update Software…") { AboutPanel.show(checkNow: true) }
                Button("Quit Vital") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 12, weight: .medium)).frame(width: 20, height: 20)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .accessibilityLabel("Vital menu")
        }
        .foregroundStyle(Color.primary.opacity(0.8))
        .padding(.horizontal, 16).padding(.vertical, 7)
        .modifier(PillBackground(reduceTransparency: reduceTransparency))
        .alert("Launch at login", isPresented: Binding(get: { loginError != nil }, set: { if !$0 { loginError = nil } })) {
            Button("OK", role: .cancel) { loginError = nil }
        } message: { Text(loginError ?? "") }
    }
    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch { loginError = "Could not change launch at login. \(error.localizedDescription)" }
        if on && SMAppService.mainApp.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

struct PillBackground: ViewModifier {
    let reduceTransparency: Bool
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Capsule().fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(Capsule().strokeBorder(.primary.opacity(0.15)))
        } else if #available(macOS 26, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content.background(.thinMaterial, in: Capsule()).overlay(Capsule().strokeBorder(.white.opacity(0.2)))
        }
    }
}
