import Testing
import Foundation
import VitalFanIPC

@Test func peersArePinnedByDeveloperNotByBuild() {
    let rule = FanService.identityRequirement(identifier: "dev.soumya.vital", team: "4W769MPDJ6")
    #expect(rule == "anchor apple generic and identifier \"dev.soumya.vital\" and certificate leaf[subject.OU] = \"4W769MPDJ6\"")
    #expect(rule?.contains("cdhash") == false)       // a build pin refuses every newer release
}

@Test func identityValuesThatCouldBreakOutOfTheRuleAreRefused() {
    #expect(FanService.identityRequirement(identifier: "a\" or anchor apple", team: "4W769MPDJ6") == nil)
    #expect(FanService.identityRequirement(identifier: "dev.soumya.vital", team: "bad team") == nil)
    #expect(FanService.identityRequirement(identifier: "dev.soumya.vital", team: "4w769mpdj6") == nil)
    #expect(FanService.identityRequirement(identifier: "", team: "4W769MPDJ6") == nil)
}

@Test func unsignedOrMissingExecutablesGetNoRequirement() {
    #expect(FanService.requirement(for: URL(fileURLWithPath: "/nonexistent/Vital")) == nil)
    #expect(FanService.bundledHelperBuild(app: URL(fileURLWithPath: "/nonexistent/Vital.app")) == nil)
}

@Test func appleSystemBinariesFallBackToTheirBuild() {
    // No team identifier on a platform binary, so the exact build is pinned.
    #expect(FanService.requirement(for: URL(fileURLWithPath: "/usr/bin/true"))?.hasPrefix("cdhash H\"") == true)
}
