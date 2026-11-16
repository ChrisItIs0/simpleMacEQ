// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SimpleMacEQ",
    platforms: [
        // Core Audio process taps require macOS 14.2.
        .macOS("14.2")
    ],
    targets: [
        .target(name: "EQCore"),
        .executableTarget(
            name: "SimpleMacEQ",
            dependencies: ["EQCore"]
        ),
        .testTarget(
            name: "EQCoreTests",
            dependencies: ["EQCore"]
        ),
    ]
)
