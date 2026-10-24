// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "globe-switch",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure logic with no system dependencies, so it can be tested without Input Monitoring.
        .target(name: "GlobeSwitchCore"),
        .executableTarget(name: "globe-switch", dependencies: ["GlobeSwitchCore"]),
        .testTarget(name: "GlobeSwitchCoreTests", dependencies: ["GlobeSwitchCore"]),
    ]
)
