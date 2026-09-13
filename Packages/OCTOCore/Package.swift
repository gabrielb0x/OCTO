// swift-tools-version: 6.2
import PackageDescription

// Platform-independent logic (models, OpenAI protocol, parsers) so it can be
// unit tested with `swift test` on macOS and Linux, without a simulator.
let package = Package(
    name: "OCTOCore",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "OCTOCore", targets: ["OCTOCore"]),
    ],
    targets: [
        .target(
            name: "OCTOCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "OCTOCoreTests",
            dependencies: ["OCTOCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
