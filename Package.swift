// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Vital",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Vital", targets: ["Vital"]),
        .executable(name: "VitalFanHelper", targets: ["VitalFanHelper"]),
    ],
    targets: [
        .target(
            name: "CVitalSensors",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation"), .linkedFramework("ApplicationServices")]),
        .target(
            name: "VitalCore",
            dependencies: ["CVitalSensors"],
            swiftSettings: [.swiftLanguageMode(.v5), .unsafeFlags(["-Osize"], .when(configuration: .release))]),
        .executableTarget(
            name: "Vital",
            dependencies: ["VitalCore", "VitalFanIPC"],
            swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "VitalFanIPC", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "VitalFanHelper", dependencies: ["VitalCore", "VitalFanIPC", "CVitalSensors"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(
            name: "VitalCoreTests",
            dependencies: ["VitalCore", "VitalFanIPC"],
            swiftSettings: [.swiftLanguageMode(.v5), .unsafeFlags(["-Osize"], .when(configuration: .release))]),
    ]
)
