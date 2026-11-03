import AppKit
import SwiftUI
import VitalCore

/// The four vital tiles double as the selector for the list below them.
enum PanelTab: String, CaseIterable, Identifiable {
    case cpu = "CPU", memory = "Memory", storage = "Storage", heat = "Heat"
    var id: String { rawValue }
    var kind: VitalKind {
        switch self { case .cpu: return .cpu; case .memory: return .memory; case .storage: return .storage; case .heat: return .heat }
    }
    var metric: RankMetric {
        switch self {
        case .memory: return .memory
        case .heat: return .power
        default: return .cpu
        }
    }
    init(_ kind: VitalKind) {
        switch kind { case .cpu: self = .cpu; case .memory: self = .memory; case .storage: self = .storage; case .heat: self = .heat }
    }
    /// From a `--tab=` argument; "Disk" (an old tab) maps to Storage.
    init?(argument: String) {
        if argument == "Disk" { self = .storage; return }
        self.init(rawValue: argument)
    }
}

struct PendingAction: Identifiable {
    enum Kind { case quit, force, quitAllUnresponsive }
    let id = UUID()
    var kind: Kind
    var groups: [AppGroup]
    var title: String {
        switch kind {
        case .quit: return "Quit \(groups.first?.name ?? "app")?"
        case .force: return "Force Quit \(groups.first?.name ?? "app")?"
        case .quitAllUnresponsive: return "Force Quit \(groups.count) not responding?"
        }
    }
    var detail: String {
        let closing = groups.count == 1 ? Self.processCount(groups[0].processes.count).map { "\($0) will close. " } ?? "" : ""
        switch kind {
        case .quit: return closing + "The app can ask you to save first."
        case .force, .quitAllUnresponsive: return closing + "Unsaved work will be lost."
        }
    }

    /// "96 processes", or nil for a single process (nothing worth saying).
    static func processCount(_ n: Int) -> String? { n > 1 ? "\(n) processes" : nil }
}

@MainActor
final class PanelModel: ObservableObject {
    @Published var snapshot: Snapshot
    @Published var history: [Double]
    @Published var tab: PanelTab = .cpu { didSet { tabChanged(from: oldValue) } }
    @Published var expanded: Set<String> = []
    @Published var showDetails = false
    @Published var showAll = false
    @Published var overview = true          // the page the panel opens on
    @Published var histories: Histories
    @Published var range: HistoryRange = .fiveMinutes
    @Published var pending: PendingAction?
    @Published var toast: String?

    let icons = NSCache<NSString, NSImage>()
    private let appState: AppState
    private let actions = ProcessActions()
    /// A day of CPU, memory, heat and network by the minute. Not published: it changes with every snapshot that already redraws the panel.
    var longHistories: LongHistories { appState.longHistories }
    var storage: StorageStore { appState.storage }
    var fanController: FanClient { appState.fanController }
    var fanAvailability: FanControlAvailability { appState.fanController.availability }
    private var toastTask: Task<Void, Never>?

    init(appState: AppState) {
        self.appState = appState
        self.snapshot = appState.latest
        self.history = appState.cpuHistory
        self.histories = appState.histories
        appState.onSnapshot = { [weak self] snap in
            guard let self else { return }
            self.snapshot = snap
            self.history = appState.cpuHistory
            if self.overview { self.histories = appState.histories }       // only the Overview page graphs them
        }
    }

    func close() {
        appState.onSnapshot = nil
        storage.cancel()                     // scans run only while the panel is open
        fanController.panelClosed()
        toastTask?.cancel()
    }

    // MARK: derived

    var headline: Headline { Health.headline(snapshot) }

    /// What is wrong with the selected vital, shown at the top of its own view. Nil when it is fine.
    var status: Headline? { Health.status(tab.kind, snapshot) }

    var ranked: [AppGroup] { Ranking.sorted(snapshot.groups, by: tab.metric) }

    func group(id: String) -> AppGroup? { snapshot.groups.first { $0.id == id } }

    /// Height the panel content wants; the controller resizes the window to it, keeping the top edge.
    var onHeight: ((CGFloat) -> Void)?
    var maxHeight: CGFloat = 600
    var minHeight: CGFloat = 480
    /// The Overview fits its content; the app lists keep a steady height between tabs.
    var floorHeight: CGFloat { overview ? 120 : minHeight }

    var unresponsiveGroups: [AppGroup] { headline.hungIDs.compactMap(group(id:)) }

    func isUnresponsive(_ g: AppGroup) -> Bool {
        g.processes.contains { snapshot.unresponsivePIDs.contains($0.pid) }
    }

    func icon(for g: AppGroup) -> NSImage {
        let key = (g.bundlePath ?? "exec:" + g.name) as NSString
        if let i = icons.object(forKey: key) { return i }
        let source = g.bundlePath.map { NSWorkspace.shared.icon(forFile: $0) } ?? NSWorkspace.shared.icon(for: .unixExecutable)
        let img = Self.thumbnail(of: source)
        icons.setObject(img, forKey: key)
        return img
    }

    /// An app icon from NSWorkspace carries every size from 16 to 1024 px (megabytes each). Keep only a
    /// 22 pt bitmap (44 px) so the full icon can be freed.
    static func thumbnail(of source: NSImage) -> NSImage {
        let pt: CGFloat = 22, px = 44
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return source }
        rep.size = NSSize(width: pt, height: pt)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(in: NSRect(x: 0, y: 0, width: pt, height: pt), from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let out = NSImage(size: NSSize(width: pt, height: pt))
        out.addRepresentation(rep)
        return out
    }

    // MARK: actions

    func toggleOverview() {
        overview.toggle()
        if overview { histories = appState.histories }
    }

    func select(_ t: PanelTab) {
        overview = false
        guard t != tab else { return }
        tab = t
        showAll = false
    }

    func toggle(_ g: AppGroup) {
        if expanded.contains(g.id) { expanded.remove(g.id) } else { expanded.insert(g.id) }
    }

    func request(_ kind: PendingAction.Kind, _ groups: [AppGroup]) {
        guard !groups.isEmpty else { return }
        pending = PendingAction(kind: kind, groups: groups)
    }

    func cancelPending() { pending = nil }

    func confirmPending() {
        guard let p = pending else { return }
        pending = nil
        Task { [weak self] in
            guard let self else { return }
            var messages: [String] = []
            for g in p.groups {
                let rows = g.processes
                let outcome: ActionOutcome
                switch p.kind {
                case .quit: outcome = await actions.quit(rows)
                case .force, .quitAllUnresponsive: outcome = await actions.forceQuit(rows)
                }
                messages.append(Self.message(for: outcome, name: g.name, forced: p.kind != .quit))
            }
            show(toast: messages.joined(separator: "\n"))
        }
    }

    static func message(for outcome: ActionOutcome, name: String, forced: Bool) -> String {
        switch outcome {
        case .gone: return forced ? "\(name) was force quit." : "\(name) quit."
        case .stillRunning: return "\(name) is still running. Try Force Quit."
        case .stuck: return "\(name) is stuck in the system (usually a disk or network volume). Only a restart or unplugging the device will clear it."
        case .denied: return "\(name) needs administrator rights to quit."
        case .protected: return "\(name) is a protected system process."
        }
    }

    private func show(toast text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            if !Task.isCancelled { self?.toast = nil }
        }
    }

    // MARK: refresh

    /// Takes a fresh sample of everything now; on the Storage tab it also rescans the folders.
    func refresh() {
        appState.sampler.refreshNow()
        if tab == .storage { storage.rescan(busy: snapshot.band != .calm) }
    }

    var isRefreshing: Bool { tab == .storage && storage.scanning }

    // MARK: storage

    /// Leaving the Storage tab does not cancel the scan: it keeps running until the panel closes.
    private func tabChanged(from old: PanelTab) {
        if tab == .storage { storage.ensureFresh(busy: snapshot.band != .calm) }
    }
}

