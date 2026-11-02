import Foundation

public protocol FanRecoveryStore {
    func load() throws -> [Int: Double]
    func save(_ modes: [Int: Double]) throws
}

/// Only the root helper uses this store. The directory is private to its effective user.
public final class FanRecoveryFile: FanRecoveryStore {
    public static let location = URL(fileURLWithPath: "/var/db/dev.soumya.vital/fan-recovery.json")
    private let url: URL
    private struct Record: Codable { var version = 1; var modes: [Int: Double] }

    public init(url: URL = FanRecoveryFile.location) { self.url = url }

    private func prepareDirectory() throws {
        let files = FileManager.default
        let directory = url.deletingLastPathComponent()
        try files.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let attributes = try files.attributesOfItem(atPath: directory.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == geteuid(),
              let mode = attributes[.posixPermissions] as? NSNumber, mode.intValue & 0o077 == 0 else {
            throw FanSessionError("Fan recovery storage has unsafe permissions. Manual control is disabled.")
        }
    }

    public func load() throws -> [Int: Double] {
        try prepareDirectory()
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == geteuid(),
              ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= 4096 else {
            throw FanSessionError("Fan recovery storage is invalid. Manual control is disabled.")
        }
        let record = try JSONDecoder().decode(Record.self, from: Data(contentsOf: url))
        guard record.version == 1, record.modes.count <= 8,
              record.modes.allSatisfy({ (0..<8).contains($0.key) && ($0.value == 0 || $0.value == 3) }) else {
            throw FanSessionError("Fan recovery storage is invalid. Manual control is disabled.")
        }
        return record.modes
    }

    public func save(_ modes: [Int: Double]) throws {
        try prepareDirectory()
        try JSONEncoder().encode(Record(modes: modes)).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let file = try FileHandle(forWritingTo: url)
        defer { try? file.close() }
        try file.synchronize()
    }
}
