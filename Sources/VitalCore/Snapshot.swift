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

    public static let empty = Snapshot(date: .distantPast, cpu: nil, memory: nil, storage: nil,
        thermal: ThermalReading(state: .nominal, sensors: [], cpuCelsius: nil, gpuCelsius: nil, hottestCelsius: nil, fans: []),
        groups: [], unresponsivePIDs: [], swapGrowthBytesPerSec: 0, band: .calm, hasProcessData: false)
}
