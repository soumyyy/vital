import Foundation

public struct LoadInput: Sendable {
    public var cpu: Double                 // 0...1
    public var pressure: MemoryPressure
    public var swapGrowthBytesPerSec: Double
    public var thermal: ThermalState
    public init(cpu: Double, pressure: MemoryPressure, swapGrowthBytesPerSec: Double, thermal: ThermalState) {
        self.cpu = cpu; self.pressure = pressure
        self.swapGrowthBytesPerSec = swapGrowthBytesPerSec; self.thermal = thermal
    }
}

/// Picks the icon band with hysteresis. Constants are the spec's starting values.
public struct LoadEvaluator {
    public static let cpuStruggleThreshold = 0.9
    public static let cpuBusyThreshold = 0.6
    public static let swapGrowthThreshold = 25_000_000.0
    public static let sustain: TimeInterval = 10
    public static let exitHold: TimeInterval = 10

    public private(set) var band: LoadBand = .calm
    private var cpuHighSince: Date?
    private var swapFastSince: Date?
    private var clearSince: Date?

    public init() {}

    @discardableResult
    public mutating func update(_ i: LoadInput, at now: Date) -> LoadBand {
        let cpuHigh = i.cpu >= Self.cpuStruggleThreshold
        let swapFast = i.swapGrowthBytesPerSec >= Self.swapGrowthThreshold
        cpuHighSince = cpuHigh ? (cpuHighSince ?? now) : nil
        swapFastSince = swapFast ? (swapFastSince ?? now) : nil

        func sustained(_ since: Date?) -> Bool {
            guard let since else { return false }
            return now.timeIntervalSince(since) >= Self.sustain
        }
        let struggling = sustained(cpuHighSince) || sustained(swapFastSince)
            || i.pressure == .critical || i.thermal >= .serious
        let busy = cpuHigh || swapFast || i.cpu >= Self.cpuBusyThreshold
            || i.pressure == .elevated || i.thermal == .fair

        let target: LoadBand = struggling ? .struggling : (busy ? .busy : .calm)
        if target >= band {
            band = target
            clearSince = nil
        } else {
            clearSince = clearSince ?? now
            if now.timeIntervalSince(clearSince!) >= Self.exitHold {
                band = target
                clearSince = nil
            }
        }
        return band
    }
}
