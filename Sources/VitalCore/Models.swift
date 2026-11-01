import Foundation

public enum MemoryPressure: Int, Comparable, Sendable {
    case normal = 0, elevated = 1, critical = 2
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

public enum ThermalState: Int, Comparable, Sendable {
    case nominal = 0, fair, serious, critical
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

public enum LoadBand: Int, Comparable, Sendable {
    case calm = 0, busy, struggling
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}
