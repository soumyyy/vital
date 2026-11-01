import Foundation
import Darwin

public struct StorageReading: Sendable {
    public var totalBytes: UInt64
    public var availableBytes: UInt64       // "available for important usage": includes purgeable space, matches Finder
    public var usedBytes: UInt64 { totalBytes > availableBytes ? totalBytes - availableBytes : 0 }
    public var usedFraction: Double { totalBytes == 0 ? 0 : Double(usedBytes) / Double(totalBytes) }
    public init(totalBytes: UInt64, availableBytes: UInt64) {
        self.totalBytes = totalBytes; self.availableBytes = availableBytes
    }
}

public struct FolderUsage: Sendable, Identifiable, Equatable {
    public var path: String
    public var bytes: UInt64
    public var id: String { path }
    public init(path: String, bytes: UInt64) { self.path = path; self.bytes = bytes }
}

public enum ScanStatus: Sendable, Equatable { case waiting, scanning, done }

public struct StorageCategory: Sendable, Identifiable {
    public var name: String
    public var bytes: UInt64              // final when done; a running total while scanning
    public var top: [FolderUsage]
    public var status: ScanStatus
    public var partial: Bool              // some folders could not be read (usually Full Disk Access)
    public var scannedAt: Date?           // when this category finished
    public var id: String { name }
    public init(name: String, bytes: UInt64, top: [FolderUsage], status: ScanStatus = .done,
                partial: Bool = false, scannedAt: Date? = nil) {
        self.name = name; self.bytes = bytes; self.top = top; self.status = status
        self.partial = partial; self.scannedAt = scannedAt
    }
}

public struct StorageBreakdown: Sendable {
    public var categories: [StorageCategory]
    public var scannedAt: Date
    public init(categories: [StorageCategory], scannedAt: Date = Date()) {
        self.categories = categories; self.scannedAt = scannedAt
    }

    public var partial: Bool { categories.contains { $0.partial } }
    public var isComplete: Bool { categories.allSatisfy { $0.status == .done } }
    public var doneCount: Int { categories.filter { $0.status == .done }.count }

    /// Used space that no finished category accounts for: system data, snapshots, swap, and unreadable folders.
    public func otherBytes(usedBytes: UInt64) -> UInt64 {
        let counted = categories.filter { $0.status == .done }.reduce(UInt64(0)) { $0 + $1.bytes }
        return usedBytes > counted ? usedBytes - counted : 0
    }

    /// A breakdown listing every name, all waiting. Used before any scan result arrives.
    public static func waiting(names: [String]) -> StorageBreakdown {
        StorageBreakdown(categories: names.map { StorageCategory(name: $0, bytes: 0, top: [], status: .waiting) })
    }

    /// Replaces categories by name with those in `update`, keeping this breakdown's order.
    /// Categories only in `update` are appended.
    public func merging(_ update: StorageBreakdown) -> StorageBreakdown {
        var out = categories
        for c in update.categories {
            if let i = out.firstIndex(where: { $0.name == c.name }) { out[i] = c } else { out.append(c) }
        }
        return StorageBreakdown(categories: out, scannedAt: max(scannedAt, update.scannedAt))
    }

    /// Marks the given categories as waiting again (for a rescan), keeping the others.
    public func resetting(_ names: Set<String>) -> StorageBreakdown {
        var b = self
        for i in b.categories.indices where names.contains(b.categories[i].name) {
            b.categories[i] = StorageCategory(name: b.categories[i].name, bytes: 0, top: [], status: .waiting)
        }
        return b
    }
}

/// When to rescan. Results stay valid for `freshFor`; categories finished earlier than that, or never
/// finished (the panel closed mid-scan), are scanned again. Finished, fresh categories are kept, so
/// reopening the panel resumes instead of starting from zero.
public enum StorageCache {
    public static let freshFor: TimeInterval = 600

    /// Names of the categories that need scanning. Empty means the cached result is good.
    public static func namesToScan(cached: StorageBreakdown?, allNames: [String], now: Date) -> [String] {
        guard let cached else { return allNames }
        return allNames.filter { name in
            guard let c = cached.categories.first(where: { $0.name == name }), c.status == .done,
                  let at = c.scannedAt else { return true }
            return now.timeIntervalSince(at) >= freshFor || now < at
        }
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

    /// Whether Vital has Full Disk Access: the system TCC database is readable only with it.
    /// nil when the answer cannot be told (the file is missing on this macOS).
    public static func hasFullDiskAccess() -> Bool? {
        let fd = open("/Library/Application Support/com.apple.TCC/TCC.db", O_RDONLY)
        if fd >= 0 { close(fd); return true }
        return (errno == EPERM || errno == EACCES) ? false : nil
    }

    /// Cloud drives (Google Drive, OneDrive, Dropbox...) live here as File Provider folders. Their files are
    /// mostly online-only placeholders, and walking them makes the provider enumerate: measured 25 s for
    /// about 1,000 entries and 0 bytes on disk. They are skipped.
    public static func cloudStoragePath(home: String = NSHomeDirectory()) -> String { home + "/Library/CloudStorage" }

    public static func defaultDefinitions(home: String = NSHomeDirectory()) -> [CategoryDefinition] {
        let lib = home + "/Library"
        let caches = lib + "/Caches", dev = lib + "/Developer"
        let cloud = cloudStoragePath(home: home)
        let docker: [String] = [home + "/.docker", lib + "/Containers/com.docker.docker",
                                lib + "/Group Containers/group.com.docker", home + "/Virtual Machines.localized",
                                home + "/Parallels"]
        let developer: [String] = [dev, home + "/.cache", home + "/.npm", home + "/.cargo",
                                   home + "/.rustup", home + "/.gradle", home + "/.m2", home + "/.cocoapods"]
        let claimed = Set([caches, cloud] + developer + docker)
        let homeClaimed = Set([lib, home + "/Documents", home + "/Desktop", home + "/Downloads", home + "/Movies",
                               home + "/Music", home + "/Pictures", home + "/Applications"] + developer + docker)
        return [
            CategoryDefinition(name: "Applications", roots: ["/Applications", home + "/Applications"]),
            CategoryDefinition(name: "Documents", roots: [home + "/Documents"]),
            CategoryDefinition(name: "Desktop and Downloads", roots: [home + "/Desktop", home + "/Downloads"]),
            CategoryDefinition(name: "Media", roots: [home + "/Movies", home + "/Music", home + "/Pictures"]),
            CategoryDefinition(name: "Developer tools", roots: developer),
            CategoryDefinition(name: "Docker and VMs", roots: docker),
            CategoryDefinition(name: "Caches", roots: [caches]),
            CategoryDefinition(name: "Library", roots: [lib], excludePaths: claimed),
            CategoryDefinition(name: "Home", roots: [home], excludePaths: homeClaimed),
            CategoryDefinition(name: "System", roots: ["/System", "/Library", "/usr", "/private", "/opt", "/bin", "/sbin"],
                               excludePaths: ["/System/Volumes"]),   // firmlinked data volume: already counted elsewhere
        ]
    }
}

/// Measures categories of folders with fts (no per-file object allocation).
///
/// Speed: a full scan is bound by file-system latency, not CPU (measured: 165 s wall, 37 s system CPU,
/// 900k context switches). So a few workers walk in parallel. Work starts as one item per top-level folder;
/// a worker hands subfolders it has not entered yet back to the queue whenever its category has nothing
/// else queued, so one huge folder (a code folder full of node_modules) is split across workers. Items are
/// taken in category order, so categories finish roughly in order and stream to the UI as they complete.
public final class StorageScanner: @unchecked Sendable {
    public static let defaultConcurrency = 4     // measured: 4 workers about 2x faster than 1; 8 no better
    private let definitions: [CategoryDefinition]
    private let concurrency: Int
    private let qos: QualityOfService

    /// `qos`: `.utility` while the user is watching the scan (about 2x faster: the kernel work can use the
    /// performance cores), `.background` when the Mac is already busy.
    public init(definitions: [CategoryDefinition] = StorageSampler.defaultDefinitions(),
                concurrency: Int = StorageScanner.defaultConcurrency, qos: QualityOfService = .utility) {
        self.definitions = definitions
        self.concurrency = max(1, concurrency)
        self.qos = qos
    }

    /// Blocks until done. Returns nil if cancelled. `progress` fires whenever a category finishes and about
    /// every `progressInterval` seconds while scanning (with running totals), on the calling thread.
    public func scan(progress: ((StorageBreakdown) -> Void)? = nil, progressInterval: TimeInterval = 0.5,
                     isCancelled: @escaping @Sendable () -> Bool = { false }) -> StorageBreakdown? {
        let work = Work(categoryCount: definitions.count)
        // Plan: one item per top-level folder. Listing roots is cheap.
        for (ci, def) in definitions.enumerated() {
            for root in def.roots {
                guard let kids = try? FileManager.default.contentsOfDirectory(atPath: root) else {
                    // A root that is missing is skipped; an existing one we cannot list marks partial.
                    if FileManager.default.fileExists(atPath: root) { work.partial[ci] = true }
                    continue
                }
                for kid in kids {
                    let path = root == "/" ? "/" + kid : root + "/" + kid
                    if def.excludePaths.contains(path) { continue }
                    work.addTop(category: ci, path: path)
                }
            }
        }
        work.stacks = work.stacks.map { Array($0.reversed()) }    // pop in listing order

        // Dedicated threads, not GCD global queues: the coordinator below blocks, and when the calling threads
        // are themselves pool threads (Swift concurrency, tests) queued work at low QoS can wait forever.
        let group = DispatchGroup()
        for i in 0..<min(concurrency, max(1, work.pendingTotal)) {
            group.enter()
            let thread = Thread { [definitions] in
                while let item = work.pop() {
                    Self.walk(item, excluding: definitions[item.category].excludePaths, work: work, isCancelled: isCancelled)
                }
                group.leave()
            }
            thread.qualityOfService = qos
            thread.name = "Vital storage scan \(i + 1)"
            thread.start()
        }

        var cancelled = false
        var lastDone = -1
        var lastEmit = Date()
        progress?(snapshot(work))                                   // the category list, all waiting, at once
        while true {
            let finished = work.waitForChange(timeout: progressInterval)
            if isCancelled() { cancelled = true; work.stopAll(); break }
            if finished { break }
            if let progress {
                let snap = snapshot(work)
                if snap.doneCount != lastDone || Date().timeIntervalSince(lastEmit) >= progressInterval * 0.9 {
                    lastDone = snap.doneCount
                    lastEmit = Date()
                    progress(snap)
                }
            }
        }
        group.wait()
        if cancelled || isCancelled() { return nil }
        let result = snapshot(work)
        progress?(result)
        return result
    }

    private func snapshot(_ work: Work) -> StorageBreakdown {
        let now = Date()
        let state = work.state()
        let cats = definitions.enumerated().map { ci, def -> StorageCategory in
            let tops = state.tops.filter { $0.category == ci }
                .map { FolderUsage(path: $0.path, bytes: $0.bytes) }
                .filter { $0.bytes > 0 }
                .sorted { $0.bytes > $1.bytes }
            let status: ScanStatus = state.outstanding[ci] == 0 ? .done : (state.started[ci] ? .scanning : .waiting)
            return StorageCategory(name: def.name, bytes: tops.reduce(0) { $0 + $1.bytes }, top: Array(tops.prefix(5)),
                                   status: status, partial: state.partial[ci],
                                   scannedAt: status == .done ? (state.doneAt[ci] ?? now) : nil)
        }
        return StorageBreakdown(categories: cats, scannedAt: now)
    }

    /// Walks one item. Directories it has not entered yet may be handed back to the queue (see `wantsDonation`).
    private static func walk(_ item: Work.Item, excluding: Set<String>, work: Work, isCancelled: () -> Bool) {
        var partial = false
        var pending: UInt64 = 0
        guard let cpath = strdup(item.path) else { work.finish(item, bytes: 0, partial: false); return }
        defer { free(cpath) }
        var argv: [UnsafeMutablePointer<CChar>?] = [cpath, nil]
        guard let fts = fts_open(&argv, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else {
            work.finish(item, bytes: 0, partial: true); return
        }
        defer { fts_close(fts) }
        var n = 0
        while let ent = fts_read(fts) {
            n += 1
            if n & 0x3FF == 0 {
                if isCancelled() { work.stopAll(); break }
                work.add(pending, top: item.top); pending = 0
            }
            switch Int32(ent.pointee.fts_info) {
            case FTS_D:
                if !excluding.isEmpty, excluding.contains(String(cString: ent.pointee.fts_path)) {
                    fts_set(fts, ent, FTS_SKIP)
                } else if ent.pointee.fts_level >= 1, work.wantsDonation(category: item.category) {
                    work.donate(Work.Item(category: item.category, top: item.top, path: String(cString: ent.pointee.fts_path)))
                    fts_set(fts, ent, FTS_SKIP)
                } else if let st = ent.pointee.fts_statp {
                    pending &+= UInt64(max(0, st.pointee.st_blocks)) * 512
                }
            case FTS_F, FTS_SL, FTS_SLNONE, FTS_DEFAULT:
                if let st = ent.pointee.fts_statp { pending &+= UInt64(max(0, st.pointee.st_blocks)) * 512 }
            case FTS_DNR, FTS_ERR, FTS_NS:
                partial = true
            default:
                break
            }
        }
        work.finish(item, bytes: pending, partial: partial)
    }

    /// Shared scan state. Every field is guarded by `cond`.
    private final class Work: @unchecked Sendable {
        struct Item { var category: Int; var top: Int; var path: String }
        struct Top { var category: Int; var path: String; var bytes: UInt64 }
        struct State { var tops: [Top]; var outstanding: [Int]; var started: [Bool]; var partial: [Bool]; var doneAt: [Date?] }

        let cond = NSCondition()
        var stacks: [[Item]]
        var tops: [Top] = []
        var outstanding: [Int]
        var started: [Bool]
        var partial: [Bool]
        var doneAt: [Date?]
        var pendingTotal = 0
        var stopped = false
        var changed = false

        init(categoryCount: Int) {
            stacks = Array(repeating: [], count: categoryCount)
            outstanding = Array(repeating: 0, count: categoryCount)
            started = Array(repeating: false, count: categoryCount)
            partial = Array(repeating: false, count: categoryCount)
            doneAt = Array(repeating: nil, count: categoryCount)
        }

        /// Planning only (single-threaded, before workers start).
        func addTop(category: Int, path: String) {
            tops.append(Top(category: category, path: path, bytes: 0))
            stacks[category].append(Item(category: category, top: tops.count - 1, path: path))
            outstanding[category] += 1
            pendingTotal += 1
        }

        private var allDone: Bool { outstanding.allSatisfy { $0 == 0 } }

        /// Next item, lowest category first. Waits while others may still donate. nil when finished or stopped.
        func pop() -> Item? {
            cond.lock(); defer { cond.unlock() }
            while true {
                if stopped { return nil }
                if let c = stacks.firstIndex(where: { !$0.isEmpty }) {
                    pendingTotal -= 1
                    started[c] = true
                    return stacks[c].removeLast()
                }
                if allDone { return nil }
                cond.wait()
            }
        }

        /// True when nothing else from this category is queued. Keeping one spare item queued for the earliest
        /// unfinished category means whichever worker frees up next helps finish it (workers always take the
        /// lowest category first), so one huge folder is split across workers instead of walked by one.
        func wantsDonation(category: Int) -> Bool {
            cond.lock(); defer { cond.unlock() }
            return !stopped && stacks[category].isEmpty
        }

        func donate(_ item: Item) {
            cond.lock()
            stacks[item.category].append(item)
            outstanding[item.category] += 1
            pendingTotal += 1
            cond.broadcast()          // the coordinator waits on the same condition; wake a worker for sure
            cond.unlock()
        }

        func add(_ bytes: UInt64, top: Int) {
            guard bytes > 0 else { return }
            cond.lock(); tops[top].bytes &+= bytes; cond.unlock()
        }

        func finish(_ item: Item, bytes: UInt64, partial isPartial: Bool) {
            cond.lock()
            tops[item.top].bytes &+= bytes
            if isPartial { partial[item.category] = true }
            outstanding[item.category] -= 1
            if outstanding[item.category] == 0 { doneAt[item.category] = Date(); changed = true; cond.broadcast() }
            cond.unlock()
        }

        func stopAll() {
            cond.lock(); stopped = true; cond.broadcast(); cond.unlock()
        }

        /// Waits until a category finishes or `timeout` passes. Returns true when everything is done (or stopped).
        func waitForChange(timeout: TimeInterval) -> Bool {
            cond.lock(); defer { cond.unlock() }
            let deadline = Date().addingTimeInterval(timeout)
            while !changed && !allDone && !stopped {
                if !cond.wait(until: deadline) { break }
            }
            changed = false
            return allDone || stopped
        }

        func state() -> State {
            cond.lock(); defer { cond.unlock() }
            return State(tops: tops, outstanding: outstanding, started: started, partial: partial, doneAt: doneAt)
        }
    }
}
