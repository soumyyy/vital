import Foundation

/// A dotted version such as "0.2.0" or "v1.4". Missing parts count as zero; a "-beta" style suffix sorts
/// before the same number without one.
public struct AppVersion: Comparable, Equatable, Sendable, CustomStringConvertible {
    public let parts: [Int]
    public let preRelease: Bool
    public let text: String

    public init?(_ raw: String) {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        let pre = s.firstIndex(where: { $0 == "-" || $0 == "+" })
        let core = pre.map { String(s[..<$0]) } ?? s
        let numbers = core.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !numbers.isEmpty, numbers.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
        parts = numbers.compactMap { $0 }
        preRelease = pre.map { s[$0] == "-" } ?? false
        text = core
    }

    public var description: String { text + (preRelease ? " (pre-release)" : "") }

    public static func < (a: AppVersion, b: AppVersion) -> Bool {
        let n = max(a.parts.count, b.parts.count)
        for i in 0..<n {
            let x = i < a.parts.count ? a.parts[i] : 0, y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y }
        }
        return a.preRelease && !b.preRelease
    }
    public static func == (a: AppVersion, b: AppVersion) -> Bool { !(a < b) && !(b < a) }
}

/// A published release that carries a downloadable app.
public struct ReleaseInfo: Equatable, Sendable {
    public var version: AppVersion
    public var tag: String
    public var notes: String
    public var pageURL: URL?
    public var assetURL: URL
    public var assetName: String
    public var assetSize: Int64?
    public var sha256: String?          // lowercase hex, when the release publishes one
}

public enum UpdateFeed {
    /// The latest published release of the Vital repository.
    public static let defaultURL = URL(string: "https://api.github.com/repos/soumyyy/vital/releases/latest")!

    /// Reads GitHub's "latest release" JSON. Drafts and pre-releases are not offered. The app must be a .zip
    /// named `Vital*.zip`; a checksum comes from the asset's `digest` or a `sha256: <hex>` line in the notes.
    public static func parse(_ data: Data) -> ReleaseInfo? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let tag = root["tag_name"] as? String, let version = AppVersion(tag),
              (root["draft"] as? Bool) != true, (root["prerelease"] as? Bool) != true,
              let assets = root["assets"] as? [[String: Any]] else { return nil }
        guard let asset = assets.first(where: {
            let name = ($0["name"] as? String) ?? ""
            return name.hasPrefix("Vital") && name.hasSuffix(".zip")
        }), let name = asset["name"] as? String,
              !name.contains("/"), !name.contains("\\"),
              let urlString = asset["browser_download_url"] as? String, let url = URL(string: urlString),
              isSecure(url) else { return nil }
        let notes = (root["body"] as? String) ?? ""
        var digest = (asset["digest"] as? String).flatMap { $0.hasPrefix("sha256:") ? String($0.dropFirst(7)) : nil }
        if digest == nil { digest = checksum(inNotes: notes) }
        return ReleaseInfo(version: version, tag: tag, notes: notes,
                           pageURL: (root["html_url"] as? String).flatMap(URL.init(string:)),
                           assetURL: url, assetName: name, assetSize: (asset["size"] as? NSNumber)?.int64Value,
                           sha256: digest?.lowercased().isValidSHA256 == true ? digest?.lowercased() : nil)
    }

    /// https, or plain http to this Mac only (so the updater can be tested against a local server).
    static func isSecure(_ url: URL) -> Bool {
        url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1"].contains(url.host ?? ""))
    }

    static func checksum(inNotes notes: String) -> String? {
        for line in notes.split(whereSeparator: \.isNewline) {
            let l = line.trimmingCharacters(in: .whitespaces).lowercased()
            guard l.hasPrefix("sha256:") else { continue }
            let hex = l.dropFirst(7).trimmingCharacters(in: .whitespaces)
            if hex.isValidSHA256 { return hex }
        }
        return nil
    }
}

extension String {
    var isValidSHA256: Bool { count == 64 && allSatisfy { $0.isHexDigit } }
}

public enum UpdateDecision: Equatable, Sendable {
    case upToDate
    case available(ReleaseInfo)
}

public enum UpdatePolicy {
    public static func decide(current: AppVersion, latest: ReleaseInfo) -> UpdateDecision {
        latest.version > current ? .available(latest) : .upToDate
    }

    /// The first words of the release notes, plain text, for the update prompt.
    public static func summary(of notes: String, limit: Int = 400) -> String {
        let lines = notes.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.lowercased().hasPrefix("sha256:") }
            .map { $0.drop(while: { $0 == "#" || $0 == " " }) }
        let text = lines.joined(separator: "\n")
        return text.count <= limit ? text : String(text.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}
