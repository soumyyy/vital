import Foundation
import Testing
@testable import VitalCore

private func setupSwap() throws -> (URL, URL, URL) {
    let work = FileManager.default.temporaryDirectory.appendingPathComponent("vital-swap-\(UUID())")
    try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    let old = work.appendingPathComponent("Vital.app")
    let new = work.appendingPathComponent("new.app")
    try Data("old".utf8).write(to: old)
    try Data("new".utf8).write(to: new)
    return (work, old, new)
}

@Test func replacementKeepsABackupUntilTheCallerFinishes() throws {
    let (work, target, new) = try setupSwap()
    defer { try? FileManager.default.removeItem(at: work) }
    try UpdateBundleSwap.replace(target, with: new, in: work)
    #expect(try String(contentsOf: target, encoding: .utf8) == "new")
    #expect(try String(contentsOf: work.appendingPathComponent("old.app"), encoding: .utf8) == "old")
}

@Test func failedReplacementPutsTheWorkingAppBack() throws {
    let (work, target, _) = try setupSwap()
    defer { try? FileManager.default.removeItem(at: work) }
    #expect(throws: UpdateInstallError.self) {
        try UpdateBundleSwap.replace(target, with: work.appendingPathComponent("missing.app"), in: work)
    }
    #expect(try String(contentsOf: target, encoding: .utf8) == "old")
}

@Test func failedExchangePreservesBothWorkingAppAndBackup() throws {
    let (work, target, new) = try setupSwap()
    defer { try? FileManager.default.removeItem(at: work) }
    #expect(throws: UpdateInstallError.self) {
        try UpdateBundleSwap.replace(target, with: new, in: work, exchange: { _, _ in
            throw NSError(domain: "test", code: 1)
        })
    }
    #expect(try String(contentsOf: target, encoding: .utf8) == "old")
    #expect(try String(contentsOf: new, encoding: .utf8) == "new")
    #expect(try String(contentsOf: work.appendingPathComponent("old.app"), encoding: .utf8) == "old")
}

private final class BrokenCopy: FileManager, @unchecked Sendable {
    override func copyItem(at source: URL, to destination: URL) throws {
        throw NSError(domain: "test", code: 1)
    }
}

@Test func failedBackupDoesNotTouchTheInstalledApp() throws {
    let (work, target, new) = try setupSwap()
    defer { try? FileManager.default.removeItem(at: work) }
    #expect(throws: (any Error).self) {
        try UpdateBundleSwap.replace(target, with: new, in: work, files: BrokenCopy())
    }
    #expect(try String(contentsOf: target, encoding: .utf8) == "old")
    #expect(try String(contentsOf: new, encoding: .utf8) == "new")
}
