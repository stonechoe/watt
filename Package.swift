// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "watt",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(name: "watt", path: "Sources"),
    ]
)
