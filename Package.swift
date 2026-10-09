// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ClipStack",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "ClipStack", path: "Sources/ClipStack")
    ]
)
