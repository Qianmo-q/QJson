// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "JSONEditor",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "JSONEditor", targets: ["JSONEditor"]),
        .library(name: "JSONCore", targets: ["JSONCore"]),
    ],
    targets: [
        .target(
            name: "JSONCore",
            path: "Sources/JSONCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "JSONEditor",
            dependencies: ["JSONCore"],
            path: "Sources/JSONEditor",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "JSONSelfTest",
            dependencies: ["JSONCore"],
            path: "Sources/JSONSelfTest",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
