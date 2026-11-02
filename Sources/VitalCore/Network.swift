import Foundation
import Darwin

public struct NetworkReading: Sendable, Equatable {
    public var downBytesPerSec: Double
    public var upBytesPerSec: Double
}

public enum NetworkMath {
    /// Interfaces that carry real traffic. Loopback, VPN tunnels and bridges would double count.
    public static func isPhysical(_ name: String) -> Bool { name.hasPrefix("en") || name.hasPrefix("pdp_ip") }

    /// Bytes moved since the previous reading, summed over the interfaces present in both. The kernel's
    /// 32-bit counters wrap at 4 GB, so a wrapped counter still gives the right delta (as long as under
    /// 4 GB moved between readings). A new interface has no previous reading and is skipped once.
    public static func delta(prev: [String: (rx: UInt32, tx: UInt32)],
                             cur: [String: (rx: UInt32, tx: UInt32)]) -> (down: UInt64, up: UInt64) {
        var down: UInt64 = 0, up: UInt64 = 0
        for (name, c) in cur {
            guard let p = prev[name] else { continue }
            down += UInt64(c.rx &- p.rx)
            up += UInt64(c.tx &- p.tx)
        }
        return (down, up)
    }
}

/// System-wide network speed from the interface counters. Public API, no permission needed.
public final class NetworkSampler {
    private var previous: [String: (rx: UInt32, tx: UInt32)]?
    private var lastTime: Date?
    private var down = TimeWindowMean(window: 5)
    private var up = TimeWindowMean(window: 5)

    public init() {}

    public func reset() { previous = nil; lastTime = nil; down = TimeWindowMean(window: 5); up = TimeWindowMean(window: 5) }

    /// nil on the first call after a reset. Speeds are averaged over 5 seconds.
    public func sample(at now: Date = Date()) -> NetworkReading? {
        let cur = Self.counters()
        defer { previous = cur; lastTime = now }
        guard let prev = previous, let last = lastTime else { return nil }
        let dt = now.timeIntervalSince(last)
        guard dt > 0 else { return nil }
        let d = NetworkMath.delta(prev: prev, cur: cur)
        return NetworkReading(downBytesPerSec: down.add(Double(d.down) / dt, at: now),
                              upBytesPerSec: up.add(Double(d.up) / dt, at: now))
    }

    static func counters() -> [String: (rx: UInt32, tx: UInt32)] {
        var out: [String: (rx: UInt32, tx: UInt32)] = [:]
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return out }
        defer { freeifaddrs(head) }
        var p = head
        while let cur = p {
            let name = String(cString: cur.pointee.ifa_name)
            if NetworkMath.isPhysical(name), let addr = cur.pointee.ifa_addr,
               addr.pointee.sa_family == UInt8(AF_LINK), let data = cur.pointee.ifa_data {
                let d = data.assumingMemoryBound(to: if_data.self).pointee
                out[name] = (d.ifi_ibytes, d.ifi_obytes)
            }
            p = cur.pointee.ifa_next
        }
        return out
    }
}
