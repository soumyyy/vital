import AppKit
import SwiftUI
import VitalCore

/// Renders the panel into a PNG without a display (layout check; glass is not drawn offscreen).
/// Usage: Vital --render-panel out.png [--tab=Heat] [--expand-first] [--details] [--more]
///        [--appearance=light|dark] [--mock=calm|busy|struggling] [--wait=seconds] [--max-height=pt]
/// `--mock` edits a live reading to stage a state for screenshots (render only, never in the app).
enum PanelRender {
    @MainActor
    static func render(to path: String) {
        let args = CommandLine.arguments
        func value(_ name: String) -> String? { args.first { $0.hasPrefix("--\(name)=") }.map { String($0.dropFirst(name.count + 3)) } }

        _ = NSApplication.shared
        let state = AppState()
        state.start()
        state.sampler.setMode(.open)
        spin(6)
        let model = PanelModel(appState: state)
        if let mock = value("mock") {
            state.onSnapshot = nil                       // freeze the staged reading
            model.snapshot = staged(mock, from: state.latest)
            if let focus = Health.headline(model.snapshot).focus, focus != .storage { model.tab = PanelTab(focus) }
        }
        if let t = value("tab"), let tab = PanelTab(argument: t) { model.tab = tab }
        if args.contains("--expand-first"), let g = model.ranked.first(where: { !$0.isAggregate }) { model.expanded.insert(g.id) }
        if args.contains("--details") { model.showDetails = true }
        if args.contains("--more") { model.showAll = true }
        if model.tab == .heat { model.fanController.refresh() }
        spin(value("wait").flatMap(Double.init) ?? 1)

        let dark = value("appearance") != "light"
        let limit = value("max-height").flatMap(Double.init).map { CGFloat($0) } ?? 680   // taller, to see below the fold
        model.maxHeight = limit
        var height: CGFloat = limit
        model.onHeight = { height = $0 }
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let root = PanelView(model: model)
            .background(dark ? Color(white: 0.16) : Color(white: 0.93))
            .environment(\.colorScheme, dark ? .dark : .light)
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        // An offscreen window gives the view one consistent effective appearance (a bare view mixes them).
        let window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 340, height: limit),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = host
        for _ in 0..<4 { host.layoutSubtreeIfNeeded(); spin(0.1) }
        window.setContentSize(NSSize(width: 340, height: min(limit, max(120, height.rounded(.up)))))
        host.layoutSubtreeIfNeeded()
        spin(0.2)
        appearance.performAsCurrentDrawingAppearance {
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            print("wrote \(path) (\(Int(host.frame.height)) pt tall)")
        }
    }

    @MainActor private static func spin(_ seconds: Double) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
    }

    /// A live reading pushed into a calm, busy or struggling state.
    private static func staged(_ mock: String, from live: Snapshot) -> Snapshot {
        var s = live
        let apps = Ranking.sorted(s.groups.filter { !$0.isAggregate && !$0.isProtected && $0.bundlePath != nil }, by: .memory)
        s.memory?.pressure = .normal
        s.thermal.state = .nominal
        s.unresponsivePIDs = []
        s.pageInBytesPerSec = 0
        if let st = s.storage { s.storage = StorageReading(totalBytes: st.totalBytes, availableBytes: st.totalBytes / 3) }
        switch mock {
        case "busy":
            s.band = .busy
            s.cpu?.total = 0.72
            if let i = s.groups.firstIndex(where: { $0.id == apps.first?.id }) { s.groups[i].cpuCores = 4.1 }
        case "struggling":
            s.band = .struggling
            s.cpu?.total = 0.97
            if let i = s.groups.firstIndex(where: { $0.id == apps.first?.id }) { s.groups[i].cpuCores = 6.8 }
            if apps.count > 1, let pid = apps[1].processes.first?.pid { s.unresponsivePIDs = [pid] }
        default:
            s.band = .calm
            let total = s.cpu?.total ?? 0
            s.cpu?.total = min(total, 0.12)
        }
        return s
    }
}
