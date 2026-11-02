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

@Test func cpuShareFormats() {
    #expect(Format.cpuShare(cores: 1.85, coreCount: 8) == "23%")
    #expect(Format.cpuShare(cores: 0.01, coreCount: 8) == "<1%")
    #expect(Format.cpuShare(cores: 0, coreCount: 8) == "0%")
    #expect(Format.ofOneCore(1.85) == "185% of a core")
    #expect(Format.coresInUse(2.7, of: 8) == "2.7 of 8 cores")
    #expect(Format.coresInUse(12, of: 8) == "8.0 of 8 cores")
}
