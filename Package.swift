// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Bilah",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Bilah",
            path: "Sources/Bilah",
            linkerSettings: [.linkedFramework("IOKit")]
        )
    ]
)
