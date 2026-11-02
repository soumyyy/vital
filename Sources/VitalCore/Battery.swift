import Foundation
import IOKit

public struct BatteryReading: Sendable, Equatable {
    public var percent: Int
    public var isCharging: Bool
    public var onPower: Bool            // plugged in
    public var watts: Double?           // power in (charging) or out (discharging), always positive
    public var minutesRemaining: Int?   // to empty on battery, to full when charging
    public var cycleCount: Int?
    public var healthFraction: Double?  // full-charge capacity compared with the design capacity, 0...1
}

public enum BatteryMath {
    /// The registry stores signed values as unsigned 64-bit two's complement (a discharge of -6399 mW reads 18446744073709545217).
    static func signed(_ v: Any?) -> Int64? {
        if let n = v as? NSNumber {
            let u = n.uint64Value
            return u > UInt64(Int64.max) ? Int64(bitPattern: u) : n.int64Value
        }
        return nil
    }
    static func int(_ v: Any?) -> Int? { signed(v).map(Int.init) }
    static func flag(_ v: Any?) -> Bool { (v as? NSNumber)?.boolValue ?? false }

    /// Builds a reading from the AppleSmartBattery registry properties. nil when there is no battery.
    public static func reading(from p: [String: Any]) -> BatteryReading? {
        guard flag(p["BatteryInstalled"]) || p["CurrentCapacity"] != nil,
              let current = int(p["CurrentCapacity"]), let max = int(p["MaxCapacity"]), max > 0 else { return nil }
        let percent = min(100, Swift.max(0, Int((Double(current) / Double(max) * 100).rounded())))
        let charging = flag(p["IsCharging"])
        let onPower = flag(p["ExternalConnected"])

        let batteryData = p["BatteryData"] as? [String: Any]
        var watts: Double?
        if let mw = signed(batteryData?["BatteryPower"] ?? p["BatteryPower"]), mw != 0 {
            watts = abs(Double(mw)) / 1000
        } else if let mv = int(p["Voltage"]), let ma = signed(p["Amperage"]), ma != 0 {
            watts = abs(Double(mv) * Double(ma)) / 1_000_000
        }

        func minutes(_ key: String) -> Int? {
            guard let m = int(p[key]), m > 0, m < 65535 else { return nil }
            return m
        }
        let minutesLeft = charging ? minutes("AvgTimeToFull") : (onPower ? nil : (minutes("AvgTimeToEmpty") ?? minutes("TimeRemaining")))

        var health: Double?
        if let nominal = int(batteryData?["NominalChargeCapacity"]), let design = int(batteryData?["DesignCapacity"]), design > 0, nominal > 0 {
            health = min(1, Double(nominal) / Double(design))
        }
        return BatteryReading(percent: percent, isCharging: charging, onPower: onPower, watts: watts,
                              minutesRemaining: minutesLeft, cycleCount: int(p["CycleCount"]), healthFraction: health)
    }
}

public enum BatterySampler {
    /// nil on Macs without a battery.
    public static func read() -> BatteryReading? {
        let service = IOServiceGetMatchingService(0, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else { return nil }
        return BatteryMath.reading(from: dict)
    }
}
