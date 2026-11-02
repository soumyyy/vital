import Testing
import Foundation
@testable import VitalCore

@Test func versionsCompareNumericallyNotAsText() {
    #expect(AppVersion("0.10.0")! > AppVersion("0.9.9")!)
    #expect(AppVersion("v1.2")! == AppVersion("1.2.0")!)
    #expect(AppVersion("1.0.0-beta")! < AppVersion("1.0.0")!)
    #expect(AppVersion("2.0")! > AppVersion("1.99.99")!)
    #expect(AppVersion("") == nil && AppVersion("abc") == nil && AppVersion("1..2") == nil && AppVersion("1.-2") == nil)
}

private func feed(tag: String = "v0.2.0", draft: Bool = false, pre: Bool = false, asset: String = "Vital-0.2.0.zip",
                  url: String = "https://github.com/soumyyy/vital/releases/download/v0.2.0/Vital-0.2.0.zip",
                  body: String = "Faster.\n\nsha256: " + String(repeating: "ab", count: 32), digest: String? = nil) -> Data {
    var a: [String: Any] = ["name": asset, "browser_download_url": url, "size": 1_000_000]
    if let digest { a["digest"] = digest }
    let root: [String: Any] = ["tag_name": tag, "draft": draft, "prerelease": pre, "body": body,
                               "html_url": "https://github.com/soumyyy/vital/releases/tag/\(tag)", "assets": [a]]
    return try! JSONSerialization.data(withJSONObject: root)
}

@Test func parsesAGitHubReleaseWithItsChecksum() {
    let r = UpdateFeed.parse(feed())!
    #expect(r.version == AppVersion("0.2.0")! && r.assetName == "Vital-0.2.0.zip")
    #expect(r.sha256 == String(repeating: "ab", count: 32))
    let d = UpdateFeed.parse(feed(body: "", digest: "sha256:" + String(repeating: "CD", count: 32)))!
    #expect(d.sha256 == String(repeating: "cd", count: 32))      // the asset's own digest, lowercased
    #expect(UpdateFeed.parse(feed(body: "no checksum here"))!.sha256 == nil)
}

@Test func refusesReleasesItShouldNotInstall() {
    #expect(UpdateFeed.parse(feed(draft: true)) == nil)
    #expect(UpdateFeed.parse(feed(pre: true)) == nil)
    #expect(UpdateFeed.parse(feed(tag: "nightly")) == nil)
    #expect(UpdateFeed.parse(feed(asset: "Vital.dmg")) == nil)
    #expect(UpdateFeed.parse(feed(url: "http://example.com/Vital-0.2.0.zip")) == nil)     // plain http
    #expect(UpdateFeed.parse(feed(url: "http://127.0.0.1:8000/Vital-0.2.0.zip")) != nil)  // this Mac only
    #expect(UpdateFeed.parse(Data("not json".utf8)) == nil)
    #expect(UpdateFeed.parse(feed(body: "sha256: nothex"))!.sha256 == nil)
}

@Test func offersOnlyNewerVersions() {
    let r = UpdateFeed.parse(feed())!
    #expect(UpdatePolicy.decide(current: AppVersion("0.1.0")!, latest: r) == .available(r))
    #expect(UpdatePolicy.decide(current: AppVersion("0.2.0")!, latest: r) == .upToDate)
    #expect(UpdatePolicy.decide(current: AppVersion("0.3.0")!, latest: r) == .upToDate)
}

@Test func summaryDropsTheChecksumLineAndTrims() {
    let s = UpdatePolicy.summary(of: "## What's new\n\n- Faster\n\nsha256: " + String(repeating: "a", count: 64))
    #expect(s == "What's new\n- Faster")
    #expect(UpdatePolicy.summary(of: String(repeating: "x", count: 900), limit: 50).count == 51)
}
