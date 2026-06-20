// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "reminder-bridge",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "BridgeCore",
            path: "Sources/BridgeCore"),
        .executableTarget(
            name: "reminderbridge",
            dependencies: ["BridgeCore"],
            path: "Sources/reminderbridge"),
        .executableTarget(
            name: "AppleBasket",
            dependencies: ["BridgeCore"],
            path: "Sources/ReminderBridgeApp")
    ]
)
