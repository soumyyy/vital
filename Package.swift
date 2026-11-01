// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Vital",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Vital", targets: ["Vital"])],
    targets: [
        .target(name: "VitalCore", swiftSettings: [.swiftLanguageMode(.v5)]),
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
