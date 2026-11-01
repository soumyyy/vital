// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Vital",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Vital", targets: ["Vital"])],
    targets: [
        .target(
            name: "CVitalSensors",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation"), .linkedFramework("ApplicationServices")]),
        .target(
            name: "VitalCore",
            dependencies: ["CVitalSensors"],
            swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(
            name: "Vital",
            dependencies: ["VitalCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(
            name: "VitalCoreTests",
            dependencies: ["VitalCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
