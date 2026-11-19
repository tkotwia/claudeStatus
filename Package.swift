// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeStatus",
    platforms: [.macOS("14.4")],
    targets: [
        .target(name: "ClaudeStatusCore"),
        .executableTarget(name: "ClaudeStatus", dependencies: ["ClaudeStatusCore"]),
        .testTarget(name: "ClaudeStatusCoreTests", dependencies: ["ClaudeStatusCore"]),
    ]
)
