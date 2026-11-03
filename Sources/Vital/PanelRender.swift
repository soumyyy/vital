import AppKit
import SwiftUI
import VitalCore

/// Renders the panel into a PNG without a display (layout check; glass is not drawn offscreen).
/// Usage: Vital --render-panel out.png [--tab=Heat] [--expand-first] [--details] [--more] [--overview]
///        [--cycle-tabs] [--range=5min|1hr|24hr] [--appearance=light|dark] [--mock=calm|busy|struggling|memory-pressure|tile-limits] [--wait=seconds] [--max-height=pt]
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
        spin(12)
        let model = PanelModel(appState: state)
        if let mock = value("mock") {
            state.onSnapshot = nil                       // freeze the staged reading
            model.snapshot = staged(mock, from: state.latest)
            if let focus = Health.headline(model.snapshot).focus, focus != .storage { model.tab = PanelTab(focus); model.overview = false }
        }
        if let t = value("tab"), let tab = PanelTab(argument: t) { model.tab = tab; model.overview = false }
        if args.contains("--expand-first"), let g = model.ranked.first(where: { !$0.isAggregate }) { model.expanded.insert(g.id) }
        if args.contains("--overview") { model.overview = true }
        if args.contains("--demo-history") {                       // five minutes of invented readings, to judge the graphs
            var h = Histories()
            let now = Date()
            for i in 0..<150 {
                let t = now.addingTimeInterval(Double(i - 150) * 2), x = Double(i)
                h.cpu.append(0.25 + 0.2 * sin(x / 9) + (i % 17 == 0 ? 0.25 : 0), at: t)
                h.memory.append(0.6 + 0.05 * sin(x / 40) + x / 2000, at: t)
                h.heat.append(40 + 6 * sin(x / 25), at: t)
                h.down.append(max(0, 2_000_000 * sin(x / 7)), at: t); h.up.append(max(0, 200_000 * sin(x / 5)), at: t)
                h.diskRead.append(max(0, 3_000_000 * sin(x / 11)), at: t); h.diskWrite.append(max(0, 1_000_000 * sin(x / 6)), at: t)
            }
            var day = LongHistories()
            for m in 0..<(24 * 60) {
                let t = now.addingTimeInterval(Double(m - 24 * 60) * 60), x = Double(m)
                day.cpu.append(0.2 + 0.15 * sin(x / 90) + (m % 240 < 20 ? 0.4 : 0), at: t)
                day.memory.append(0.55 + 0.1 * sin(x / 300), at: t)
                day.heat.append(42 + 8 * sin(x / 200), at: t)
                day.down.append(max(0, 1_500_000 * sin(x / 40)), at: t); day.up.append(max(0, 150_000 * sin(x / 25)), at: t)
            }
            state.onSnapshot = nil
            state.stage(longHistories: day)
            model.histories = h
        }
        if let r = value("range"), let range = HistoryRange.allCases.first(where: { $0.rawValue.replacingOccurrences(of: " ", with: "") == r }) { model.range = range }
        if args.contains("--details") { model.showDetails = true }
        if args.contains("--more") { model.showAll = true }
        if model.tab == .heat { model.fanController.refresh() }
        spin(value("wait").flatMap(Double.init) ?? 1)

        let dark = value("appearance") != "light"
        let limit = value("max-height").flatMap(Double.init).map { CGFloat($0) } ?? 680   // taller, to see below the fold
        model.maxHeight = limit
        model.minHeight = min(480, limit)
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
        window.setContentSize(NSSize(width: 340, height: min(limit, max(model.floorHeight, height.rounded(.up)))))
        host.layoutSubtreeIfNeeded()
        spin(0.2)
        func capture(_ destination: String) {
            appearance.performAsCurrentDrawingAppearance {
                guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
                host.cacheDisplay(in: host.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: destination))
                print("wrote \(destination) (\(Int(host.frame.height)) pt tall)")
            }
        }
        if args.contains("--cycle-tabs") {
            // Switch the same hosted view, including a warning and long values. Separate launches
            // cannot catch layout state carried over from another tab.
            let base = (path as NSString).deletingPathExtension
            for (index, tab) in (PanelTab.allCases + [.cpu]).enumerated() {
                model.select(tab)
                for _ in 0..<4 { host.layoutSubtreeIfNeeded(); spin(0.1) }
                capture("\(base)-\(index)-\(tab.rawValue.lowercased()).png")
            }
        }
        capture(path)
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
        case "tile-limits":
            s.band = .busy
            s.cpu?.total = 1
            if var memory = s.memory {
                memory.usedBytes = memory.totalBytes
                s.memory = memory
            }
            s.memory?.pressure = .elevated
            if let st = s.storage { s.storage = StorageReading(totalBytes: st.totalBytes, availableBytes: 0) }
            s.thermal.hottestCelsius = nil
            s.thermal.state = .critical
        case "memory-pressure":
            s.band = .busy
            s.memory?.pressure = .elevated
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
