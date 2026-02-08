// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "power",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(name: "power", path: "Sources"),
    ]
)
