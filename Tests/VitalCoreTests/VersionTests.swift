import Testing
@testable import VitalCore

@Test func versionIsSet() {
    #expect(!VitalInfo.version.isEmpty)
}
