// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LinkSentinel",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "LinkSentinel", targets: ["LinkSentinel"])],
    targets: [
        .target(name: "MonitorCore", linkerSettings: [.linkedLibrary("sqlite3")]),
        .executableTarget(name: "LinkSentinel", dependencies: ["MonitorCore"]),
        .testTarget(name: "MonitorCoreTests", dependencies: ["MonitorCore"])
    ]
)
