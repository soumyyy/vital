import Foundation
import AppKit
import CVitalSensors

/// Owns all sampling. Runs on a utility-QoS queue, never the main thread. Publishes immutable snapshots.
public final class Sampler {
    private let queue = DispatchQueue(label: "dev.soumya.vital.sampler", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var gate = TickGate()
    private var mode: SamplerMode = .closed
    private var multiplier = 1.0
    private var running = false

    private let cpu = CPUSampler()
    private let processes = ProcessSampler()
    private var load = LoadEvaluator()
    private var lastSwap: (bytes: UInt64, time: Date)?
    private var lastStorage: (reading: StorageReading, time: Date)?
    private var primedProcesses = false
    private var observers: [NSObjectProtocol] = []

    private let lock = NSLock()
    private var _latest = Snapshot.empty
    public var latest: Snapshot { lock.lock(); defer { lock.unlock() }; return _latest }
    private let onSnapshot: @Sendable (Snapshot) -> Void

    public init(onSnapshot: @escaping @Sendable (Snapshot) -> Void) { self.onSnapshot = onSnapshot }

    public func start() {
        queue.async { [self] in
            guard !running else { return }
            running = true
            observeSleepWake()
            scheduleTimer()
            tick()
        }
    }

    public func stop() {
        queue.async { [self] in
            running = false
            timer?.cancel(); timer = nil
            observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
            observers = []
        }
    }

    public func setMode(_ newMode: SamplerMode) {
        queue.async { [self] in
            guard newMode != mode else { return }
            mode = newMode
            multiplier = 1
            if newMode == .closed { processes.reset(); primedProcesses = false }
            if running { scheduleTimer(); tick() }
        }
    }

    private func scheduleTimer() {
        timer?.cancel()
        let interval = SamplerPolicy.baseInterval(mode) * multiplier
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(Int(interval * 200)))
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    private func observeSleepWake() {
        let nc = NSWorkspace.shared.notificationCenter
        let pause: (Notification) -> Void = { [weak self] _ in
            self?.queue.async { self?.timer?.cancel(); self?.timer = nil }
        }
        let resume: (Notification) -> Void = { [weak self] _ in
            self?.queue.async {
                guard let self, self.running else { return }
                // Counters are meaningless across sleep: drop all deltas and start clean.
                self.cpu.reset(); self.processes.reset(); self.primedProcesses = false; self.lastSwap = nil
                self.scheduleTimer(); self.tick()
            }
        }
        observers = [
            nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: nil, using: pause),
            nc.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: nil, using: pause),
            nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: nil, using: resume),
            nc.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: nil, using: resume),
        ]
    }

    private func tick() {
        guard gate.begin() else { return }
        let started = Date()
        defer { gate.end() }

        let cpuReading = cpu.sample()
        let memory = MemorySampler.sample()
        let open = mode == .open

        var swapGrowth = 0.0
        if let memory {
            if let last = lastSwap {
                let dt = started.timeIntervalSince(last.time)
                if dt > 0 { swapGrowth = max(0, (Double(memory.swapUsedBytes) - Double(last.bytes)) / dt) }
            }
            lastSwap = (memory.swapUsedBytes, started)
        }

        let thermal = ThermalSampler.read(includeSensors: open)

        var storage = lastStorage?.reading
        if storage == nil || open && started.timeIntervalSince(lastStorage!.time) > 30 || started.timeIntervalSince(lastStorage?.time ?? .distantPast) > 120 {
            if let r = StorageSampler.capacity() { storage = r; lastStorage = (r, started) }
        }

        var groups: [AppGroup] = []
        var unresponsive = Set<Int32>()
        var hasProcessData = false
        if open {
            var sample = processes.sample()
            let me = getpid()
            sample.rows.removeAll { $0.pid == me }       // Vital never lists itself
            hasProcessData = primedProcesses
            primedProcesses = true
            if hasProcessData {
                let sysCores = cpuReading.map { $0.total * Double($0.perCore.count) }
                groups = Grouping.group(sample.rows, systemCPUCores: sysCores, memoryUsedBytes: memory?.usedBytes)
                for g in groups where g.bundlePath != nil {
                    for p in g.processes where NSRunningApplication(processIdentifier: p.pid)?.activationPolicy == .regular {
                        if vs_app_unresponsive(p.pid) == 1 { unresponsive.insert(p.pid) }
                    }
                }
            }
        }

        let band = load.update(LoadInput(cpu: cpuReading?.total ?? 0,
                                         pressure: memory?.pressure ?? .normal,
                                         swapGrowthBytesPerSec: swapGrowth,
                                         thermal: thermal.state), at: started)

        let snap = Snapshot(date: started, cpu: cpuReading, memory: memory, storage: storage, thermal: thermal,
                            groups: groups, unresponsivePIDs: unresponsive, swapGrowthBytesPerSec: swapGrowth,
                            band: band, hasProcessData: hasProcessData)
        lock.lock(); _latest = snap; lock.unlock()
        onSnapshot(snap)

        let newMultiplier = SamplerPolicy.adapt(multiplier: multiplier, tickDuration: Date().timeIntervalSince(started),
                                                base: SamplerPolicy.baseInterval(mode))
        if newMultiplier != multiplier { multiplier = newMultiplier; if running { scheduleTimer() } }
    }
}
