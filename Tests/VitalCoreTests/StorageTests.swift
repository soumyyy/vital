import Testing
import Foundation
@testable import VitalCore

private func makeTree() throws -> String {
    let root = NSTemporaryDirectory() + "vital-test-\(UUID().uuidString)"
    let fm = FileManager.default
    for d in ["apps/Big.app", "apps/Small.app", "docs", "lib/Caches", "lib/Other"] {
        try fm.createDirectory(atPath: "\(root)/\(d)", withIntermediateDirectories: true)
    }
    func write(_ rel: String, mb: Int) throws {
        try Data(repeating: 7, count: mb * 1_048_576).write(to: URL(fileURLWithPath: "\(root)/\(rel)"))
    }
    try write("apps/Big.app/blob", mb: 3)
    try write("apps/Small.app/blob", mb: 1)
    try write("docs/a.bin", mb: 2)
    try write("lib/Caches/c.bin", mb: 4)
    try write("lib/Other/o.bin", mb: 5)
    return root
}

@Test func scannerCategorizesAndRanksFolders() throws {
    let root = try makeTree()
    defer { try? FileManager.default.removeItem(atPath: root) }
    let defs = [CategoryDefinition(name: "Apps", roots: ["\(root)/apps"]),
                CategoryDefinition(name: "Docs", roots: ["\(root)/docs"])]
    let result = StorageScanner(definitions: defs).scan()!
    let apps = result.categories[0]
    #expect(apps.top.map { ($0.path as NSString).lastPathComponent } == ["Big.app", "Small.app"])
    #expect(apps.bytes >= 4 * 1_048_576 && apps.bytes < 5 * 1_048_576 + 200_000)
    #expect(result.categories[1].bytes >= 2 * 1_048_576)
    #expect(result.isComplete && !result.partial)
    #expect(result.categories.allSatisfy { $0.status == .done })
}

@Test func excludedPathsAreNotDoubleCounted() throws {
    let root = try makeTree()
    defer { try? FileManager.default.removeItem(atPath: root) }
    let defs = [CategoryDefinition(name: "Library", roots: ["\(root)/lib"], excludePaths: ["\(root)/lib/Caches"])]
    let result = StorageScanner(definitions: defs).scan()!
    #expect(result.categories[0].bytes >= 5 * 1_048_576 && result.categories[0].bytes < 6 * 1_048_576)
}

@Test func cancellationReturnsNil() throws {
    let root = try makeTree()
    defer { try? FileManager.default.removeItem(atPath: root) }
    for i in 0..<3000 { FileManager.default.createFile(atPath: "\(root)/docs/f\(i)", contents: Data([1])) }
    let defs = [CategoryDefinition(name: "Docs", roots: ["\(root)/docs"])]
    #expect(StorageScanner(definitions: defs).scan(isCancelled: { true }) == nil)
}

@Test func unreadableFolderMarksPartial() throws {
    let root = try makeTree()
    defer {
        chmod("\(root)/docs/locked", 0o755)
        try? FileManager.default.removeItem(atPath: root)
    }
    try FileManager.default.createDirectory(atPath: "\(root)/docs/locked/inner", withIntermediateDirectories: true)
    chmod("\(root)/docs/locked", 0o000)
    let defs = [CategoryDefinition(name: "Docs", roots: ["\(root)/docs"])]
    #expect(StorageScanner(definitions: defs).scan()!.partial)
}

@Test func otherBytesNeverNegative() {
    let b = StorageBreakdown(categories: [StorageCategory(name: "x", bytes: 900, top: []),
                                          StorageCategory(name: "y", bytes: 50, top: [], status: .scanning)])
    #expect(b.otherBytes(usedBytes: 1000) == 100)       // the unfinished category is not counted yet
    #expect(b.otherBytes(usedBytes: 500) == 0)
}

@Test func parallelScanMatchesSerialScan() throws {
    let root = try makeTree()
    defer { try? FileManager.default.removeItem(atPath: root) }
    // A deep, bushy folder so workers split it between them.
    for a in 0..<6 { for b in 0..<6 {
        let dir = "\(root)/docs/deep/a\(a)/b\(b)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 100_000).write(to: URL(fileURLWithPath: dir + "/f"))
    } }
    let defs = [CategoryDefinition(name: "Apps", roots: ["\(root)/apps"]),
                CategoryDefinition(name: "Docs", roots: ["\(root)/docs"]),
                CategoryDefinition(name: "Lib", roots: ["\(root)/lib"], excludePaths: ["\(root)/lib/Caches"])]
    let serial = StorageScanner(definitions: defs, concurrency: 1).scan()!
    let parallel = StorageScanner(definitions: defs, concurrency: 4).scan()!
    #expect(serial.categories.map(\.bytes) == parallel.categories.map(\.bytes))
    #expect(serial.categories.map { $0.top.map(\.path) } == parallel.categories.map { $0.top.map(\.path) })
    #expect(parallel.categories[1].top.first?.path == "\(root)/docs/deep")   // subfolders roll up to their top folder
    #expect(parallel.categories[2].bytes < 6 * 1_048_576)                     // exclusion holds in every worker
}

@Test func progressListsEveryCategoryFirstThenStreamsResults() throws {
    let root = try makeTree()
    defer { try? FileManager.default.removeItem(atPath: root) }
    let defs = [CategoryDefinition(name: "Apps", roots: ["\(root)/apps"]),
                CategoryDefinition(name: "Docs", roots: ["\(root)/docs"]),
                CategoryDefinition(name: "Missing", roots: ["\(root)/nope"])]
    var updates: [StorageBreakdown] = []
    let result = StorageScanner(definitions: defs).scan(progress: { updates.append($0) })!
    #expect(updates.first?.categories.map(\.name) == ["Apps", "Docs", "Missing"])
    #expect(updates.last?.isComplete == true)
    #expect(result.isComplete && result.doneCount == 3)
    #expect(result.categories[2].bytes == 0 && !result.categories[2].partial)   // a missing root is not an error
    #expect(result.categories.allSatisfy { $0.scannedAt != nil })
}

@Test func mergingReplacesByNameAndKeepsOrder() {
    let old = StorageBreakdown.waiting(names: ["A", "B", "C"])
    let update = StorageBreakdown(categories: [StorageCategory(name: "B", bytes: 7, top: [], scannedAt: Date())])
    let merged = old.merging(update)
    #expect(merged.categories.map(\.name) == ["A", "B", "C"])
    #expect(merged.categories[1].bytes == 7 && merged.categories[1].status == .done)
    #expect(merged.categories[0].status == .waiting && !merged.isComplete)
    let reset = merged.resetting(["B"])
    #expect(reset.categories[1].status == .waiting && reset.categories[1].bytes == 0)
}

@Test func cacheKeepsFreshCategoriesAndResumesTheRest() {
    let now = Date(timeIntervalSince1970: 10_000)
    let names = ["A", "B", "C", "D"]
    #expect(StorageCache.namesToScan(cached: nil, allNames: names, now: now) == names)
    let cached = StorageBreakdown(categories: [
        StorageCategory(name: "A", bytes: 1, top: [], scannedAt: now.addingTimeInterval(-60)),         // fresh
        StorageCategory(name: "B", bytes: 1, top: [], scannedAt: now.addingTimeInterval(-601)),        // stale
        StorageCategory(name: "C", bytes: 1, top: [], status: .scanning),                              // interrupted
    ])
    #expect(StorageCache.namesToScan(cached: cached, allNames: names, now: now) == ["B", "C", "D"])
    let allFresh = StorageBreakdown(categories: names.map { StorageCategory(name: $0, bytes: 1, top: [], scannedAt: now) })
    #expect(StorageCache.namesToScan(cached: allFresh, allNames: names, now: now).isEmpty)
    // A clock that went backwards does not keep results forever.
    #expect(StorageCache.namesToScan(cached: allFresh, allNames: names, now: now.addingTimeInterval(-5)) == names)
}

@Test func cloudDrivesAreSkipped() {
    let lib = StorageSampler.defaultDefinitions(home: "/Users/x").first { $0.name == "Library" }!
    #expect(lib.excludePaths.contains("/Users/x/Library/CloudStorage"))
}

@Test func capacityOfRootIsSane() {
    let r = StorageSampler.capacity()!
    #expect(r.totalBytes > r.availableBytes && r.usedFraction > 0 && r.usedFraction < 1)
}

@Test func systemCategoryDoesNotWalkIntoTheDataVolume() {
    let system = StorageSampler.defaultDefinitions().first { $0.name == "System" }!
    #expect(system.excludePaths.contains("/System/Volumes"))
}

@Test func personalFoldersNeedConsent() {
    let defs = StorageSampler.defaultDefinitions()
    let needing = Set(defs.filter(\.requiresConsent).map(\.name))
    #expect(needing == ["Documents", "Desktop and Downloads", "Photos, Music and Movies"])
    let none = StorageSampler.partition(defs, consented: [])
    #expect(!none.scan.contains { $0.requiresConsent })
    #expect(Set(none.skipped) == needing)
    let some = StorageSampler.partition(defs, consented: ["Documents"])
    #expect(some.scan.contains { $0.name == "Documents" })
    #expect(!some.skipped.contains("Documents"))
}

@Test func defaultScanNeverEntersAppDataOrPersonalFolders() {
    let home = "/Users/test"
    let defs = StorageSampler.defaultDefinitions(home: home)
    let allowed = StorageSampler.partition(defs, consented: []).scan
    let roots = allowed.flatMap(\.roots)
    for guarded in ["/Documents", "/Desktop", "/Downloads", "/Pictures", "/Music", "/Movies"] {
        #expect(!roots.contains(home + guarded))
    }
    let library = defs.first { $0.name == "Library" }!
    for folder in ["Containers", "Group Containers", "Mobile Documents", "Mail", "Messages", "Safari", "Photos"] {
        #expect(library.excludePaths.contains(home + "/Library/" + folder))
    }
    #expect(!defs.first { $0.name == "Docker and VMs" }!.roots.contains { $0.contains("/Containers") })
}

@Test func skippedCategoriesAreNotCountedAndCompleteTheScan() {
    var b = StorageBreakdown.waiting(names: ["A", "B"]).marking(skipped: ["B"])
    b.categories[0] = StorageCategory(name: "A", bytes: 100, top: [], status: .done, scannedAt: Date())
    #expect(b.isComplete && b.hasSkipped && b.scannableCount == 1 && b.doneCount == 1)
    #expect(b.otherBytes(usedBytes: 150) == 50)
    let back = b.marking(skipped: [])
    #expect(back.categories[1].status == .waiting)
}
