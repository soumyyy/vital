import Foundation
import CVitalSensors

public enum SensorKind: Sendable { case cpu, gpu, battery, storage, other }

public struct SensorReading: Sendable {
    public var name: String
    public var celsius: Double
    public var kind: SensorKind
}

public struct FanReading: Sendable {
    public var index: Int
    public var rpm: Double
    public var minRPM: Double?
    public var maxRPM: Double?
}

public struct ThermalReading: Sendable {
    public var state: ThermalState
    public var sensors: [SensorReading]
    public var cpuCelsius: Double?
    public var gpuCelsius: Double?
    public var hottestCelsius: Double?
    public var fans: [FanReading]
}

public enum ThermalBand: Sendable { case green, yellow, red }

public enum ThermalMath {
    /// Rejects NaN, zero, negative and absurd readings. Never plot these.
    public static func isValid(celsius v: Double) -> Bool { v.isFinite && v > 5 && v < 130 }

    public static func classify(sensorName n: String) -> SensorKind {
        let l = n.lowercased()
        if l.contains("gpu") { return .gpu }
        if l.contains("tdie") || l.contains("pacc") || l.contains("eacc") || l.contains("cpu") || l.contains("soc") { return .cpu }
        if l.contains("gas gauge") || l.contains("battery") { return .battery }
        if l.contains("nand") || l.contains("ssd") { return .storage }
        return .other
    }

    /// CPU and GPU are the hottest valid die sensors of that kind. Hottest overall considers only CPU and GPU
    /// (battery and storage run on their own scale), falling back to any valid sensor.
    public static func summarize(_ sensors: [SensorReading]) -> (cpu: Double?, gpu: Double?, hottest: Double?) {
        let valid = sensors.filter { isValid(celsius: $0.celsius) }
        let cpu = valid.filter { $0.kind == .cpu }.map(\.celsius).max()
        let gpu = valid.filter { $0.kind == .gpu }.map(\.celsius).max()
        let die = [cpu, gpu].compactMap { $0 }
        let hottest = die.max() ?? valid.map(\.celsius).max()
        return (cpu, gpu, hottest)
    }

    /// 30...100 °C mapped to 0...1 for the scale marker.
    public static func scaleFraction(celsius: Double) -> Double { min(1, max(0, (celsius - 30) / 70)) }

    public static func band(celsius: Double) -> ThermalBand {
        celsius <= 65 ? .green : (celsius <= 85 ? .yellow : .red)
    }

    public static func band(state: ThermalState) -> ThermalBand {
        switch state {
        case .nominal: return .green
        case .fair: return .yellow
        case .serious, .critical: return .red
        }
    }

    /// Decodes an SMC value to a number. Apple Silicon fan keys are `flt ` (little-endian float32).
    public static func decodeSMC(type: String, bytes: [UInt8]) -> Double? {
        switch type {
        case "flt ":
            guard bytes.count >= 4 else { return nil }
            let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            let v = Double(Float(bitPattern: bits))
            return v.isFinite ? v : nil
        case "ui8 ": return bytes.first.map(Double.init)
        case "ui16":
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case "fpe2":   // Intel fan rpm: unsigned 14.2 fixed point, big endian
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4
        default: return nil
        }
    }
}

public enum ThermalSampler {
    public static func state() -> ThermalState {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .nominal
        }
    }

    public static func read(includeSensors: Bool = true) -> ThermalReading {
        guard includeSensors else {
            return ThermalReading(state: state(), sensors: [], cpuCelsius: nil, gpuCelsius: nil, hottestCelsius: nil, fans: [])
        }
        let sensors = readSensors()
        let s = ThermalMath.summarize(sensors)
        return ThermalReading(state: state(), sensors: sensors, cpuCelsius: s.cpu, gpuCelsius: s.gpu,
                              hottestCelsius: s.hottest, fans: readFans())
    }

    public static func readSensors() -> [SensorReading] {
        let nameLen = Int(VS_NAME_LEN)
        var names = [CChar](repeating: 0, count: Int(VS_MAX_SENSORS) * nameLen)
        var values = [Double](repeating: 0, count: Int(VS_MAX_SENSORS))
        let count = Int(vs_hid_temperatures(&names, &values))
        return (0..<min(count, Int(VS_MAX_SENSORS))).map { i in
            let name = names.withUnsafeBufferPointer { String(cString: $0.baseAddress! + i * nameLen) }
            return SensorReading(name: name, celsius: values[i], kind: ThermalMath.classify(sensorName: name))
        }
    }

    /// Fans from the SMC. Empty on fanless Macs or when the SMC is not readable.
    public static func readFans() -> [FanReading] {
        guard let count = smcNumber("FNum"), count >= 1, count <= 8 else { return [] }
        return (0..<Int(count)).compactMap { i in
            guard let rpm = smcNumber("F\(i)Ac"), rpm.isFinite, rpm >= 0, rpm < 20_000 else { return nil }
            func limit(_ k: String) -> Double? { smcNumber("F\(i)\(k)").flatMap { $0 > 0 && $0 < 20_000 ? $0 : nil } }
            return FanReading(index: i, rpm: rpm, minRPM: limit("Mn"), maxRPM: limit("Mx"))
        }
    }

    static func smcNumber(_ key: String) -> Double? {
        var type = [CChar](repeating: 0, count: 5)
        var size: UInt32 = 0
        var bytes = [UInt8](repeating: 0, count: 32)
        guard vs_smc_read(key, &type, &size, &bytes) == 0 else { return nil }
        return ThermalMath.decodeSMC(type: String(cString: type), bytes: Array(bytes.prefix(Int(size))))
    }
}
