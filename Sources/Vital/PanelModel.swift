import AppKit
import SwiftUI
import VitalCore

enum PanelTab: String, CaseIterable, Identifiable {
    case cpu = "CPU", memory = "Memory", storage = "Storage", heat = "Heat"
    var id: String { rawValue }
    var metric: RankMetric { self == .memory ? .memory : (self == .heat ? .power : .cpu) }
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
        switch kind {
        case .quit: return "The app can ask you to save first."
        case .force, .quitAllUnresponsive: return "Unsaved work will be lost."
        }
    }
}

@MainActor
final class PanelModel: ObservableObject {
    @Published var snapshot: Snapshot
    @Published var history: [Double]
    @Published var tab: PanelTab = .cpu { didSet { tabChanged(from: oldValue) } }
    @Published var expanded: Set<String> = []
    @Published var pending: PendingAction?
    @Published var toast: String?

    let icons = NSCache<NSString, NSImage>()
    private let appState: AppState
    private let actions = ProcessActions()
    var storage: StorageStore { appState.storage }
    var fanAvailability: FanControlAvailability { appState.fanController.availability }
    private var toastTask: Task<Void, Never>?

    init(appState: AppState) {
        self.appState = appState
        self.snapshot = appState.latest
        self.history = appState.cpuHistory
        appState.onSnapshot = { [weak self] snap in
            guard let self else { return }
            self.snapshot = snap
            self.history = appState.cpuHistory
        }
    }

    func close() {
        appState.onSnapshot = nil
        storage.cancel()                     // scans run only while the panel is open
        toastTask?.cancel()
    }

    // MARK: derived

    var ranked: [AppGroup] { Ranking.sorted(snapshot.groups, by: tab.metric) }

    var unresponsiveGroups: [AppGroup] {
        snapshot.groups.filter { g in g.processes.contains { snapshot.unresponsivePIDs.contains($0.pid) } && !g.isProtected }
    }

    func isUnresponsive(_ g: AppGroup) -> Bool {
        g.processes.contains { snapshot.unresponsivePIDs.contains($0.pid) }
    }

    func icon(for g: AppGroup) -> NSImage {
        let key = (g.bundlePath ?? "exec:" + g.name) as NSString
        if let i = icons.object(forKey: key) { return i }
        let img = g.bundlePath.map { NSWorkspace.shared.icon(forFile: $0) }
            ?? NSWorkspace.shared.icon(for: .unixExecutable)
        img.size = NSSize(width: 22, height: 22)
        icons.setObject(img, forKey: key)
        return img
    }

    // MARK: actions

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

