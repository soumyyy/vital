import SwiftUI
import ServiceManagement
import VitalCore

struct PanelView: View {
    @ObservedObject var model: PanelModel
    @State private var contentHeight: CGFloat = 0
    @State private var chrome: CGFloat = 0          // everything except the scrolling list

    /// The list scrolls only when the panel would grow past its maximum height.
    private var scrollHeight: CGFloat { min(contentHeight, max(120, model.maxHeight - chrome)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HeadlineView(model: model)
            VitalTiles(model: model)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    BreakdownView(model: model)
                    DetailsSection(model: model)
                }
                .background(GeometryReader { g in Color.clear.preference(key: PanelSizes.self, value: PanelSizes(content: g.size.height)) })
            }
            .frame(height: scrollHeight)
            .background(GeometryReader { g in Color.clear.preference(key: PanelSizes.self, value: PanelSizes(scroll: g.size.height)) })
            if let p = model.pending { ConfirmBar(model: model, pending: p) }
            else if let t = model.toast { ToastBar(text: t) }
            FloatingPill(model: model, storage: model.storage).frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 14).padding(.top, 16).padding(.bottom, 12)
        .frame(width: 340)
        .background(GeometryReader { g in Color.clear.preference(key: PanelSizes.self, value: PanelSizes(root: g.size.height)) })
        .onPreferenceChange(PanelSizes.self) { s in
            contentHeight = s.content
            chrome = s.root - s.scroll
            model.onHeight?(s.root)
        }
        .panelBackground()
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(.easeOut(duration: 0.15), value: model.pending?.id)
    }
}

/// Heights reported from one layout pass: the whole panel, the list's visible frame and the list's content.
struct PanelSizes: PreferenceKey, Equatable {
    var root: CGFloat = 0, scroll: CGFloat = 0, content: CGFloat = 0
    static let defaultValue = PanelSizes()
    static func reduce(value: inout PanelSizes, nextValue: () -> PanelSizes) {
        let n = nextValue()
        value = PanelSizes(root: max(value.root, n.root), scroll: max(value.scroll, n.scroll), content: max(value.content, n.content))
    }
}

/// One sentence about the whole Mac. When something is wrong it names the app and offers to quit it;
/// when apps hang it turns into the tinted "struggling" strip with Force Quit.
struct HeadlineView: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        let h = model.headline
        let hung = model.unresponsiveGroups
        let culprit = h.culpritID.flatMap(model.group(id:))
        let alarming = h.level == .critical
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: symbol(h.level))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.color(h.level))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(h.title).font(Typo.large).fixedSize(horizontal: false, vertical: true)
                    if let d = h.detail {
                        Text(d).font(Typo.medium).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if !hung.isEmpty {
                Button(hung.count == 1 ? "Force Quit \(hung[0].name)" : "Force Quit \(hung.count) not responding") {
                    model.request(.quitAllUnresponsive, hung)
                }
                .buttonStyle(PillButton(destructive: true)).padding(.leading, 25)
            } else if let g = culprit, h.level > .good {
                Button("Quit \(g.name)…") { model.request(.quit, [g]) }
                    .buttonStyle(PillButton()).padding(.leading, 25)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(alarming ? 12 : 0)
        .padding(.horizontal, alarming ? 0 : 4)
        .background {
            if alarming { RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.red.opacity(0.14)) }
        }
        .accessibilityElement(children: .contain)
    }

    private func symbol(_ l: HealthLevel) -> String {
        switch l {
        case .good: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.circle.fill"
        case .critical: return "exclamationmark.triangle.fill"
        }
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

            Menu {
                Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: { setLaunchAtLogin($0) }))
                Divider()
                Button("About Vital") { NSApp.orderFrontStandardAboutPanel(nil) }
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
    }
    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch { NSLog("Vital: launch at login failed: \(error.localizedDescription)") }
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
