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
    let b = StorageBreakdown(categories: [StorageCategory(name: "x", bytes: 900, top: [])],
                             partial: false, scannedAt: Date(), isComplete: true)
    #expect(b.otherBytes(usedBytes: 1000) == 100)
    #expect(b.otherBytes(usedBytes: 500) == 0)
}

@Test func capacityOfRootIsSane() {
    let r = StorageSampler.capacity()!
    #expect(r.totalBytes > r.availableBytes && r.usedFraction > 0 && r.usedFraction < 1)
}
