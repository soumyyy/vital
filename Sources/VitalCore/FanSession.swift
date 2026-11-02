import Foundation
import CVitalSensors

public protocol FanHardware {
    func number(_ key: String) -> Double?
    func write(_ key: String, value: Double) throws
}

public struct SMCFanHardware: FanHardware {
    public init() {}
    public func number(_ key: String) -> Double? { ThermalSampler.smcNumber(key) }
    public func write(_ key: String, value: Double) throws {
        var type = [CChar](repeating: 0, count: 5)
        var size: UInt32 = 0
        var bytes = [UInt8](repeating: 0, count: 32)
        guard vs_smc_read(key, &type, &size, &bytes) == 0 else { throw FanSessionError("Fan control key is unavailable.") }
        switch (String(cString: type), size) {
        case ("ui8 ", 1) where value == 0 || value == 1 || value == 3: bytes[0] = UInt8(value)
        case ("flt ", 4):
            let bits = Float(value).bitPattern
            bytes[0] = UInt8(truncatingIfNeeded: bits); bytes[1] = UInt8(truncatingIfNeeded: bits >> 8)
            bytes[2] = UInt8(truncatingIfNeeded: bits >> 16); bytes[3] = UInt8(truncatingIfNeeded: bits >> 24)
        case ("fpe2", 2) where value >= 0 && value <= 16383:
            let bits = UInt16(value * 4)
            bytes[0] = UInt8(bits >> 8); bytes[1] = UInt8(truncatingIfNeeded: bits)
        default: throw FanSessionError("This Mac's fan control format is unsupported.")
        }
        let result = vs_smc_write(key, size, &bytes)
        guard result == 0 else {
            NSLog("Fan write rejected: %@ (SMC result %d)", key, result)
            throw FanSessionError("macOS refused the fan change. Try Auto, then reconnect.")
        }
    }
}

public struct FanSessionError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// Confined to the helper's serial queue. No caller-supplied SMC keys or limits reach the writer.
public final class FanSession {
    private let hardware: FanHardware
    private let clock: () -> TimeInterval
    private let hot: () -> Bool
    private var originalAuto: [Int: Double] = [:]
    public private(set) var targets: [Int: Double] = [:]
    public private(set) var resetError: String?
    private var heartbeat: TimeInterval = 0
    private var lastTick: TimeInterval
    private var lastChange: TimeInterval = -.infinity

    public init(hardware: FanHardware = SMCFanHardware(), clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                hot: @escaping () -> Bool = { ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical }) {
        self.hardware = hardware; self.clock = clock; self.hot = hot; lastTick = clock()
    }
    public func renew() { heartbeat = clock() }
    public func set(fan: Int, rpm: Double) throws {
        guard (0..<8).contains(fan), let count = hardware.number("FNum"),
              count.isFinite, count >= 1, count <= 8, count.rounded() == count, Double(fan) < count else {
            throw FanSessionError("Fan is unavailable.")
        }
        if rpm == -1 { try restore(fan); return }
        guard !hot() else { reset(); throw FanSessionError("The Mac is hot. Fans are managed automatically.") }
        if let resetError { throw FanSessionError(resetError) }
        guard clock() - lastChange >= 0.2 else { throw FanSessionError("Wait a moment before changing the fan again.") }
        guard let target = FanSafety.target(requested: rpm, minRPM: hardware.number("F\(fan)Mn"), maxRPM: hardware.number("F\(fan)Mx")) else {
            throw FanSessionError("Fan limits or requested speed are invalid.")
        }
        let modeKey = "F\(fan)Md"
        guard let mode = hardware.number(modeKey), mode == 0 || mode == 3 || (mode == 1 && originalAuto[fan] != nil) else {
            throw FanSessionError("Fan is unsupported or controlled by another app. Select Auto there first.")
        }
        if originalAuto[fan] == nil { originalAuto[fan] = mode }
        lastChange = clock()
        do {
            try hardware.write(modeKey, value: 1)
            try hardware.write("F\(fan)Tg", value: target)
            // Verify the complete mode/target transaction; firmware may not latch mode until a
            // target is present. Give the controller a bounded interval to publish its new state.
            guard verify({
                guard hardware.number(modeKey) == 1, let actual = hardware.number("F\(fan)Tg") else { return false }
                return abs(actual - target) < 1
            }) else { throw FanSessionError("Fan controller did not retain the requested mode and speed.") }
            targets[fan] = target
            renew()
        } catch {
            reset()
            throw FanSessionError(error.localizedDescription + (resetError.map { " " + $0 } ?? ""))
        }
    }
    private func restore(_ fan: Int) throws {
        guard let mode = originalAuto[fan] else { return }
        try hardware.write("F\(fan)Md", value: mode)
        guard verify({ hardware.number("F\(fan)Md") == mode }) else {
            throw FanSessionError("Fan controller did not return to Auto.")
        }
        originalAuto.removeValue(forKey: fan)
        targets.removeValue(forKey: fan)
        if originalAuto.isEmpty { resetError = nil }
    }
    /// The SMC can acknowledge a write before publishing the changed value.
    private func verify(_ matches: () -> Bool) -> Bool {
        for attempt in 0..<20 {
            if matches() { return true }
            if attempt < 19 { Thread.sleep(forTimeInterval: 0.05) }
        }
        return false
    }

    public func reset() {
        for fan in Array(originalAuto.keys) {
            do { try restore(fan) }
            catch { resetError = "Could not restore Auto. Quit other fan tools and restart the Mac if this persists." }
        }
    }
    public func tick() {
        let now = clock()
        if !originalAuto.isEmpty && (hot() || now - heartbeat > 15 || now - lastTick > 10 || resetError != nil) { reset() }
        lastTick = now
    }
}
