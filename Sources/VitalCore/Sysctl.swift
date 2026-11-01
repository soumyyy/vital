import Foundation

enum Sysctl {
    static func int(_ name: String) -> Int? {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        if sysctlbyname(name, &value, &size, nil, 0) == 0 { return Int(value) }
        var v32: Int32 = 0
        size = MemoryLayout<Int32>.size
        if sysctlbyname(name, &v32, &size, nil, 0) == 0 { return Int(v32) }
        return nil
    }

    static func string(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }
}
