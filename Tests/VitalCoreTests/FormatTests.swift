import Testing
@testable import VitalCore

@Test func bytesDecimal() {
    #expect(Format.bytes(0, base: .decimal) == "0 B")
    #expect(Format.bytes(999, base: .decimal) == "999 B")
    #expect(Format.bytes(1_500_000_000, base: .decimal) == "1.5 GB")
    #expect(Format.bytes(412_000_000_000, base: .decimal) == "412 GB")
}

@Test func bytesBinary() {
    #expect(Format.bytes(8 * 1024 * 1024 * 1024, base: .binary) == "8.0 GB")
    #expect(Format.bytes(512 * 1024 * 1024, base: .binary) == "512 MB")
}

@Test func percentAndRPM() {
    #expect(Format.percent(0.345) == "35%")
    #expect(Format.percent(1.2) == "100%")
    #expect(Format.percent(-0.1) == "0%")
    #expect(Format.rpm(2100) == "2,100 rpm")
}
