import Foundation
import VitalCore

/// Owns the storage breakdown for the whole app run, so results survive closing and reopening the panel.
/// Scans run only while the panel is open (started from the Storage tab, cancelled when the panel closes,
/// not when the tab changes). Finished categories are cached for `StorageCache.freshFor`; a scan that was
/// cancelled resumes with only the unfinished categories. The cached result is a few kilobytes.
@MainActor
final class StorageStore: ObservableObject {
    @Published private(set) var breakdown: StorageBreakdown?
    @Published private(set) var scanning = false
    @Published private(set) var startedAt: Date?
    @Published private(set) var capacity: StorageReading?
    @Published private(set) var fullDiskAccess: Bool?

    private var generation = 0
    private var cancelFlag: AtomicFlag?
    private let names = StorageSampler.defaultDefinitions().map(\.name)

    /// Called when the Storage tab is shown. Starts or resumes a scan unless the cache is fresh.
    func ensureFresh(busy: Bool) {
        capacity = StorageSampler.capacity() ?? capacity
        guard !scanning else { return }
        let toScan = StorageCache.namesToScan(cached: breakdown, allNames: names, now: Date())
        if !toScan.isEmpty { start(toScan, busy: busy) }
    }

    /// Throws away the cache and scans everything again.
    func rescan(busy: Bool) {
        capacity = StorageSampler.capacity() ?? capacity
        stop()
        start(names, busy: busy)
    }

    /// Called when the panel closes. Keeps finished categories; unfinished ones go back to waiting.
    func cancel() {
        guard scanning else { return }
        stop()
        if let b = breakdown {
            breakdown = b.resetting(Set(b.categories.filter { $0.status != .done }.map(\.name)))
        }
    }

    private func stop() {
        cancelFlag?.set()
        cancelFlag = nil
        generation += 1
        scanning = false
    }

    private func start(_ scanNames: [String], busy: Bool) {
        generation += 1
        let gen = generation
        let flag = AtomicFlag()
        cancelFlag = flag
        breakdown = (breakdown ?? .waiting(names: names)).resetting(Set(scanNames))
        scanning = true
        startedAt = Date()
        fullDiskAccess = StorageSampler.hasFullDiskAccess()
        let defs = StorageSampler.defaultDefinitions().filter { scanNames.contains($0.name) }
        let qos: QualityOfService = busy ? .background : .utility     // never compete with a Mac that is already busy
        let thread = Thread { [weak self] in
            let result = StorageScanner(definitions: defs, qos: qos).scan(progress: { update in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.apply(update, generation: gen) } }
            }, isCancelled: { flag.isSet })
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.finish(result, generation: gen) } }
        }
        thread.qualityOfService = qos
        thread.name = "Vital storage scan"
        thread.start()
    }

    private func apply(_ update: StorageBreakdown, generation gen: Int) {
        guard gen == generation, let b = breakdown else { return }
        breakdown = b.merging(update)
    }

    private func finish(_ result: StorageBreakdown?, generation gen: Int) {
        guard gen == generation else { return }      // a newer scan, or a cancel, owns the state now
        if let result, let b = breakdown { breakdown = b.merging(result) }
        scanning = false
    }
}

final class AtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func set() { lock.lock(); value = true; lock.unlock() }
}
