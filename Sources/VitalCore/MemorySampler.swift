import Foundation
import Darwin

public struct VMStats: Sendable {
    public var pageSize: UInt64
    public var internalPages: UInt64, purgeablePages: UInt64
    public var wiredPages: UInt64, compressorPages: UInt64
    public var pageIns: UInt64 = 0          // cumulative pages read back from disk (including swap)
    public init(pageSize: UInt64, internalPages: UInt64, purgeablePages: UInt64,
                wiredPages: UInt64, compressorPages: UInt64, pageIns: UInt64 = 0) {
        self.pageIns = pageIns
        self.pageSize = pageSize; self.internalPages = internalPages; self.purgeablePages = purgeablePages
        self.wiredPages = wiredPages; self.compressorPages = compressorPages
    }
}

public struct MemoryReading: Sendable {
    public var usedBytes: UInt64
    public var totalBytes: UInt64
    public var compressedBytes: UInt64
    public var swapUsedBytes: UInt64
    public var swapTotalBytes: UInt64
    public var pressure: MemoryPressure
    public var pageIns: UInt64 = 0
    public var pageSize: UInt64 = 16384
    public var usedFraction: Double { totalBytes == 0 ? 0 : min(1, Double(usedBytes) / Double(totalBytes)) }
}

public enum MemoryMath {
    /// Bytes per second the system read back from disk (page-ins). Rising page-ins with swap in use mean
    /// the Mac is short of memory and is thrashing. 0 if the counter went backwards.
    public static func pageInBytesPerSec(prev: UInt64, cur: UInt64, pageSize: UInt64, seconds: Double) -> Double {
        guard seconds > 0, cur >= prev else { return 0 }
        return Double(cur - prev) * Double(pageSize) / seconds
    }

    /// Matches Activity Monitor's "Memory Used": app memory + wired + compressed.
    public static func usedBytes(_ s: VMStats) -> UInt64 {
        let app = s.internalPages >= s.purgeablePages ? s.internalPages - s.purgeablePages : 0
        return (app + s.wiredPages + s.compressorPages) * s.pageSize
    }

    /// kern.memorystatus_vm_pressure_level: 1 normal, 2 warning, 4 critical.
    public static func pressure(kernelLevel: Int?) -> MemoryPressure {
        switch kernelLevel {
        case 4?: return .critical
        case 2?: return .elevated
        default: return .normal
        }
    }
}

public enum MemorySampler {
    public static func sample() -> MemoryReading? {
        guard let stats = readVMStats() else { return nil }
        let total = UInt64(Sysctl.int("hw.memsize") ?? 0)
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        let haveSwap = sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0
        return MemoryReading(
            usedBytes: MemoryMath.usedBytes(stats),
            totalBytes: total,
            compressedBytes: stats.compressorPages * stats.pageSize,
            swapUsedBytes: haveSwap ? swap.xsu_used : 0,
            swapTotalBytes: haveSwap ? swap.xsu_total : 0,
            pressure: MemoryMath.pressure(kernelLevel: Sysctl.int("kern.memorystatus_vm_pressure_level")),
            pageIns: stats.pageIns, pageSize: stats.pageSize)
    }

    static func readVMStats() -> VMStats? {
        var info = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        return VMStats(pageSize: UInt64(vm_kernel_page_size),
                       internalPages: UInt64(info.internal_page_count),
                       purgeablePages: UInt64(info.purgeable_count),
                       wiredPages: UInt64(info.wire_count),
                       compressorPages: UInt64(info.compressor_page_count),
                       pageIns: UInt64(info.pageins))
    }
}
