// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SOLID",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SOLID",
            path: "Sources/SOLID",
            linkerSettings: [.linkedFramework("CoreServices")]
        )
    ]
)
