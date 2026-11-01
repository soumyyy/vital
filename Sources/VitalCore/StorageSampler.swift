import Foundation
import Darwin

public struct StorageReading: Sendable {
    public var totalBytes: UInt64
    public var availableBytes: UInt64       // "available for important usage": includes purgeable space, matches Finder
    public var usedBytes: UInt64 { totalBytes > availableBytes ? totalBytes - availableBytes : 0 }
    public var usedFraction: Double { totalBytes == 0 ? 0 : Double(usedBytes) / Double(totalBytes) }
}

public struct FolderUsage: Sendable, Identifiable {
    public var path: String
    public var bytes: UInt64
    public var id: String { path }
}

public struct StorageCategory: Sendable, Identifiable {
    public var name: String
    public var bytes: UInt64
    public var top: [FolderUsage]
    public var id: String { name }
}

public struct StorageBreakdown: Sendable {
    public var categories: [StorageCategory]
    public var partial: Bool          // some folders could not be read (Full Disk Access)
    public var scannedAt: Date
    public var isComplete: Bool

    public func otherBytes(usedBytes: UInt64) -> UInt64 {
        let counted = categories.reduce(UInt64(0)) { $0 + $1.bytes }
        return usedBytes > counted ? usedBytes - counted : 0
    }
}

public struct CategoryDefinition: Sendable {
    public var name: String
    public var roots: [String]
    public var excludePaths: Set<String>
    public init(name: String, roots: [String], excludePaths: Set<String> = []) {
        self.name = name; self.roots = roots; self.excludePaths = excludePaths
    }
}

public enum StorageSampler {
    public static func capacity(of path: String = "/") -> StorageReading? {
        let url = URL(fileURLWithPath: path)
        guard let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey,
                                                         .volumeAvailableCapacityForImportantUsageKey,
                                                         .volumeAvailableCapacityKey]),
              let total = v.volumeTotalCapacity, total > 0 else { return nil }
        let avail = v.volumeAvailableCapacityForImportantUsage ?? Int64(v.volumeAvailableCapacity ?? 0)
        return StorageReading(totalBytes: UInt64(total), availableBytes: UInt64(max(0, avail)))
    }

    public static func defaultDefinitions(home: String = NSHomeDirectory()) -> [CategoryDefinition] {
        let lib = home + "/Library"
        let caches = lib + "/Caches", dev = lib + "/Developer"
        let docker: [String] = [home + "/.docker", lib + "/Containers/com.docker.docker",
                                lib + "/Group Containers/group.com.docker", home + "/Virtual Machines.localized",
                                home + "/Parallels"]
        let developer: [String] = [dev, home + "/.cache", home + "/.npm", home + "/.cargo",
                                   home + "/.rustup", home + "/.gradle", home + "/.m2", home + "/.cocoapods"]
        let claimed = Set([caches] + developer + docker)
        return [
            CategoryDefinition(name: "Applications", roots: ["/Applications", home + "/Applications"]),
            CategoryDefinition(name: "Documents", roots: [home + "/Documents"]),
            CategoryDefinition(name: "Desktop and Downloads", roots: [home + "/Desktop", home + "/Downloads"]),
            CategoryDefinition(name: "Media", roots: [home + "/Movies", home + "/Music", home + "/Pictures"]),
            CategoryDefinition(name: "Developer", roots: developer),
            CategoryDefinition(name: "Docker and VMs", roots: docker),
            CategoryDefinition(name: "Caches", roots: [caches]),
            CategoryDefinition(name: "Library", roots: [lib], excludePaths: claimed),
            CategoryDefinition(name: "System", roots: ["/System", "/Library", "/usr", "/private", "/opt", "/bin", "/sbin"]),
        ]
    }
}

/// Walks folders with fts (no per-file object allocation). Run at background QoS; cancelable.
public final class StorageScanner {
    private let definitions: [CategoryDefinition]
    public init(definitions: [CategoryDefinition] = StorageSampler.defaultDefinitions()) {
        self.definitions = definitions
    }

    /// Returns nil if cancelled. `progress` fires after each category with the partial result.
    public func scan(progress: ((StorageBreakdown) -> Void)? = nil,
                     isCancelled: () -> Bool = { false }) -> StorageBreakdown? {
        var categories: [StorageCategory] = []
        var partial = false
        for def in definitions {
            var folders: [FolderUsage] = []
            for root in def.roots {
                guard let kids = try? FileManager.default.contentsOfDirectory(atPath: root) else {
                    // A root that is itself a file or missing is skipped; unreadable existing dirs mark partial.
                    if FileManager.default.fileExists(atPath: root) { partial = true }
                    continue
                }
                for kid in kids {
                    let path = root == "/" ? "/" + kid : root + "/" + kid
                    if isCancelled() { return nil }
                    if def.excludePaths.contains(path) { continue }
                    guard let size = Self.allocatedSize(of: path, excluding: def.excludePaths,
                                                        isCancelled: isCancelled, partial: &partial) else { return nil }
                    if size > 0 { folders.append(FolderUsage(path: path, bytes: size)) }
                }
            }
            folders.sort { $0.bytes > $1.bytes }
            categories.append(StorageCategory(name: def.name, bytes: folders.reduce(0) { $0 + $1.bytes },
                                              top: Array(folders.prefix(5))))
            progress?(StorageBreakdown(categories: categories, partial: partial, scannedAt: Date(),
                                       isComplete: categories.count == definitions.count))
        }
        return StorageBreakdown(categories: categories, partial: partial, scannedAt: Date(), isComplete: true)
    }

    /// Allocated bytes under `path` (st_blocks * 512), staying on one volume. nil if cancelled.
    static func allocatedSize(of path: String, excluding: Set<String>,
                              isCancelled: () -> Bool, partial: inout Bool) -> UInt64? {
        guard let cpath = strdup(path) else { return 0 }
        defer { free(cpath) }
        var argv: [UnsafeMutablePointer<CChar>?] = [cpath, nil]
        guard let fts = fts_open(&argv, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { partial = true; return 0 }
        defer { fts_close(fts) }
        var total: UInt64 = 0
        var n = 0
        while let ent = fts_read(fts) {
            n += 1
            if n & 0x3FF == 0 && isCancelled() { return nil }
            switch Int32(ent.pointee.fts_info) {
            case FTS_D:
                if !excluding.isEmpty, excluding.contains(String(cString: ent.pointee.fts_path)) {
                    fts_set(fts, ent, FTS_SKIP)
                } else if let st = ent.pointee.fts_statp {
                    total &+= UInt64(max(0, st.pointee.st_blocks)) * 512
                }
            case FTS_F, FTS_SL, FTS_SLNONE, FTS_DEFAULT:
                if let st = ent.pointee.fts_statp { total &+= UInt64(max(0, st.pointee.st_blocks)) * 512 }
            case FTS_DNR, FTS_ERR, FTS_NS:
                partial = true
            default:
                break
            }
        }
        return total
    }
}
