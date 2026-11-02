import Foundation

public enum Grouping {
    public static let aggregateID = "aggregate:system"

    /// Top-level `.app` bundle containing `path`, or nil. Uses the first `.app` component so helpers
    /// nested inside an app (Chrome Helper.app inside Chrome.app) group under the outer app.
    public static func bundlePath(of path: String) -> String? {
        guard let range = path.range(of: ".app/") else {
            return path.hasSuffix(".app") ? path : nil
        }
        return String(path[path.startIndex..<range.lowerBound]) + ".app"
    }

    public static func appName(bundlePath: String) -> String {
        let last = (bundlePath as NSString).lastPathComponent
        return last.hasSuffix(".app") ? String(last.dropLast(4)) : last
    }

    /// Groups processes by app. Processes outside any bundle join the group of their responsible
    /// process (for example Safari's WebContent), else group by name.
    /// `systemCPUCores` and `memoryUsedBytes`, when given, add the "System and other users" row
    /// holding whatever the readable processes do not account for (never negative).
    public static func group(_ rows: [ProcessRow], systemCPUCores: Double?, memoryUsedBytes: UInt64?,
                             selfPid: Int32 = getpid()) -> [AppGroup] {
        let byPid = Dictionary(rows.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })

        func groupID(_ row: ProcessRow, depth: Int = 0) -> (id: String, name: String, bundle: String?) {
            if let b = bundlePath(of: row.path) { return ("app:" + b, appName(bundlePath: b), b) }
            if depth < 4, let r = row.responsiblePid, r != row.pid, r > 1, let parent = byPid[r] {
                return groupID(parent, depth: depth + 1)
            }
            return ("proc:" + row.name, row.name, nil)
        }

        var groups: [String: AppGroup] = [:]
        var order: [String] = []
        for row in rows {
            let g = groupID(row)
            if groups[g.id] == nil {
                groups[g.id] = AppGroup(id: g.id, name: g.name, bundlePath: g.bundle)
                order.append(g.id)
            }
            groups[g.id]!.processes.append(row)
        }

        var result: [AppGroup] = order.map { id in
            var g = groups[id]!
            g.cpuCores = g.processes.reduce(0) { $0 + $1.cpuCores }
            g.footprintBytes = g.processes.reduce(0) { $0 + $1.footprintBytes }
            let watts = g.processes.compactMap(\.watts)
            g.watts = watts.isEmpty ? nil : watts.reduce(0, +)
            g.wakeupsPerSec = g.processes.reduce(0) { $0 + $1.wakeupsPerSec }
            g.isProtected = g.processes.contains { Protection.isProtected(pid: $0.pid, name: $0.name, selfPid: selfPid) }
            g.processes.sort { $0.cpuCores > $1.cpuCores }
            return g
        }

        if let sys = systemCPUCores, let mem = memoryUsedBytes {
            let readableCPU = result.reduce(0) { $0 + $1.cpuCores }
            let readableMem = result.reduce(UInt64(0)) { $0 + $1.footprintBytes }
            result.append(AppGroup(id: aggregateID, name: "System and other users",
                                   cpuCores: max(0, sys - readableCPU),
                                   footprintBytes: mem > readableMem ? mem - readableMem : 0,
                                   isProtected: true, isAggregate: true))
        }
        return result
    }
}
