import Testing
@testable import VitalCore

private func s(_ name: String, _ c: Double) -> SensorReading {
    SensorReading(name: name, celsius: c, kind: ThermalMath.classify(sensorName: name))
}

@Test func rejectsImplausibleTemperatures() {
    for v in [Double.nan, .infinity, 0, -5, 4.9, 130, 400] { #expect(!ThermalMath.isValid(celsius: v)) }
    for v in [20.0, 58.5, 105] { #expect(ThermalMath.isValid(celsius: v)) }
}

@Test func classifiesSensorNames() {
    #expect(ThermalMath.classify(sensorName: "PMU tdie3") == .cpu)
    #expect(ThermalMath.classify(sensorName: "pACC MTR Temp Sensor1") == .cpu)
    #expect(ThermalMath.classify(sensorName: "eACC MTR Temp Sensor0") == .cpu)
    #expect(ThermalMath.classify(sensorName: "GPU MTR Temp Sensor2") == .gpu)
    #expect(ThermalMath.classify(sensorName: "gas gauge battery") == .battery)
    #expect(ThermalMath.classify(sensorName: "NAND CH0 temp") == .storage)
    #expect(ThermalMath.classify(sensorName: "PMU tcal") == .other)
}

@Test func summaryIgnoresInvalidAndBatteryForHottest() {
    let r = ThermalMath.summarize([s("PMU tdie1", 58), s("PMU tdie2", 61), s("GPU MTR Temp Sensor0", 52),
                                   s("gas gauge battery", 90), s("PMU tdie9", .nan), s("PMU tdie8", 0)])
    #expect(r.cpu == 61 && r.gpu == 52 && r.hottest == 61)
}

@Test func summaryFallsBackToAnySensorThenNil() {
    #expect(ThermalMath.summarize([s("NAND CH0 temp", 40)]).hottest == 40)
    #expect(ThermalMath.summarize([]).hottest == nil)
    #expect(ThermalMath.summarize([s("PMU tdie1", .nan)]).hottest == nil)
}

@Test func scaleAndBands() {
    #expect(ThermalMath.scaleFraction(celsius: 30) == 0)
    #expect(ThermalMath.scaleFraction(celsius: 100) == 1)
    #expect(ThermalMath.scaleFraction(celsius: 20) == 0 && ThermalMath.scaleFraction(celsius: 200) == 1)
    #expect(ThermalMath.band(celsius: 65) == .green)
    #expect(ThermalMath.band(celsius: 65.1) == .yellow)
    #expect(ThermalMath.band(celsius: 85) == .yellow)
    #expect(ThermalMath.band(celsius: 85.1) == .red)
    #expect(ThermalMath.band(state: .fair) == .yellow && ThermalMath.band(state: .critical) == .red)
}

@Test func decodesSMCTypes() {
    // 2100.0 as little-endian float32 = 0x45034000 -> bytes 00 40 03 45
    #expect(ThermalMath.decodeSMC(type: "flt ", bytes: [0x00, 0x40, 0x03, 0x45]) == 2100)
    #expect(ThermalMath.decodeSMC(type: "flt ", bytes: [0x00, 0x00, 0xC0, 0x7F]) == nil)   // NaN
    #expect(ThermalMath.decodeSMC(type: "ui8 ", bytes: [2]) == 2)
    #expect(ThermalMath.decodeSMC(type: "fpe2", bytes: [0x20, 0x00]) == 2048)
    #expect(ThermalMath.decodeSMC(type: "zzzz", bytes: [1, 2]) == nil)
    #expect(ThermalMath.decodeSMC(type: "flt ", bytes: [1]) == nil)
}
