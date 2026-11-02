import Foundation

public enum FanMode: Equatable, Sendable {
    case auto
    case manual(rpm: Double)
}

public enum FanControlAvailability: Equatable, Sendable {
    case available
    case unavailable(reason: String)
}

public enum FanControlError: Error, Equatable, Sendable {
    case notAvailable
    case invalidTarget
}

/// Seam for changing fan speed. Reading fans needs no privileges and lives in ThermalSampler; writing
/// does (macOS answers kIOReturnNotPrivileged to an unprivileged SMC write), so a real implementation
/// would be a privileged helper. See docs/superpowers/specs/2026-11-02-fan-control-helper.md.
public protocol FanController: Sendable {
    var availability: FanControlAvailability { get }
    func setMode(fan: Int, mode: FanMode) async throws
}

/// Used until a privileged helper exists. Never pretends to change anything.
public struct NoopFanController: FanController {
    public init() {}
    public var availability: FanControlAvailability {
        .unavailable(reason: "Changing fan speed needs an administrator helper, which is not installed. macOS manages the fans automatically.")
    }
    public func setMode(fan: Int, mode: FanMode) async throws { throw FanControlError.notAvailable }
}

public enum FanSafety {
    /// A requested manual speed, clamped into the fan's own limits. Never below the system minimum
    /// (below it the fan could stall under load) and never above the maximum. nil for an unusable request.
    public static func target(requested: Double, minRPM: Double?, maxRPM: Double?) -> Double? {
        guard requested.isFinite, let lo = minRPM, let hi = maxRPM, lo > 0, hi > lo else { return nil }
        return min(hi, max(lo, requested))
    }
}
