import Foundation

public enum SamplerMode: Sendable { case closed, open }

public enum SamplerPolicy {
    /// Panel open: every 2 s (the panel re-renders on each reading, so this halves its CPU cost).
    public static let openInterval: TimeInterval = 2
    /// Panel closed and the Mac calm: every 15 s. Anything busy brings it back to 5 s.
    public static let closedCalmInterval: TimeInterval = 15
    public static let closedBusyInterval: TimeInterval = 5
    /// How often the (comparatively costly) "not responding" check runs while the panel is open.
    public static let unresponsiveCheckInterval: TimeInterval = 6
    public static let maxBackoff: Double = 4

    public static func baseInterval(_ mode: SamplerMode, band: LoadBand = .calm) -> TimeInterval {
        if mode == .open { return openInterval }
        return band == .calm ? closedCalmInterval : closedBusyInterval
    }

    /// Backs the interval off when a tick takes a large share of it, so Vital never competes with a
    /// struggling system. Doubles while a tick costs more than 25% of the interval, relaxes when under 10%.
    public static func adapt(multiplier: Double, tickDuration: TimeInterval, base: TimeInterval) -> Double {
        let interval = base * multiplier
        if tickDuration > interval * 0.25 { return min(maxBackoff, multiplier * 2) }
        if tickDuration < interval * 0.10 { return max(1, multiplier / 2) }
        return multiplier
    }
}

/// Lets a tick start only if the previous one has finished. Overlapping ticks are skipped, never queued.
public struct TickGate {
    private var running = false
    public private(set) var skipped = 0
    public init() {}
    public mutating func begin() -> Bool {
        if running { skipped += 1; return false }
        running = true
        return true
    }
    public mutating func end() { running = false }
}
