import Foundation

public enum FanControlAvailability: Equatable, Sendable {
    case available
    case unavailable(reason: String)
}

public enum FanSafety {
    /// A requested manual speed, clamped into the fan's own limits. Never below the system minimum
    /// (below it the fan could stall under load) and never above the maximum. nil for an unusable request.
    public static func target(requested: Double, minRPM: Double?, maxRPM: Double?) -> Double? {
        guard requested.isFinite, let lo = minRPM, let hi = maxRPM, lo.isFinite, hi.isFinite, lo > 0, hi > lo else { return nil }
        return min(hi, max(lo, requested))
    }
}
