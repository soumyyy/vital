import AppKit
import VitalCore

/// Lives for the whole app run: owns the sampler and fans snapshots out to whoever is listening.
@MainActor
final class AppState {
    private(set) var sampler: Sampler!
    private(set) var latest = Snapshot.empty
    private(set) var cpuHistory: [Double] = []
    var onSnapshot: ((Snapshot) -> Void)?
    var onBandChange: ((LoadBand) -> Void)?
    private var band: LoadBand = .calm
    private static let historyLimit = 60

    init() {
        sampler = Sampler { [weak self] snap in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.receive(snap) } }
        }
    }

    func start() { sampler.start() }

    private func receive(_ snap: Snapshot) {
        latest = snap
        if let c = snap.cpu {
            cpuHistory.append(c.total)
            if cpuHistory.count > Self.historyLimit { cpuHistory.removeFirst(cpuHistory.count - Self.historyLimit) }
        }
        if snap.band != band { band = snap.band; onBandChange?(band) }
        onSnapshot?(snap)
    }
}
