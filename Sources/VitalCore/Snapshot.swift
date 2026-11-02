import Foundation

public struct Snapshot: Sendable {
    public var date: Date
    public var cpu: CPUReading?
    public var memory: MemoryReading?
    public var storage: StorageReading?
    public var thermal: ThermalReading
    public var groups: [AppGroup]             // empty while the panel is closed
    public var unresponsivePIDs: Set<Int32>
    public var swapGrowthBytesPerSec: Double
    public var band: LoadBand
    public var hasProcessData: Bool           // false for the first open tick (no deltas yet)
    public var network: NetworkReading?       // only while the panel is open
    public var battery: BatteryReading?       // nil on Macs without a battery, and while the panel is closed
    public var sleepBlockers: [Int32: SleepBlock]
    public var pageInBytesPerSec: Double = 0   // memory read back from disk, system-wide

    public static let empty = Snapshot(date: .distantPast, cpu: nil, memory: nil, storage: nil,
        thermal: ThermalReading(state: .nominal, sensors: [], cpuCelsius: nil, gpuCelsius: nil, hottestCelsius: nil, fans: []),
        groups: [], unresponsivePIDs: [], swapGrowthBytesPerSec: 0, band: .calm, hasProcessData: false,
        network: nil, battery: nil, sleepBlockers: [:])
}
