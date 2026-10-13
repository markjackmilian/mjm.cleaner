// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MjmCleanerKit",
    defaultLocalization: "it",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "CleanerCore", targets: ["CleanerCore"]),
    ],
    targets: [
        // Module map verso la zlib di sistema: Foundation non sa scrivere gzip.
        .systemLibrary(name: "CZlib", path: "Sources/CZlib"),
        .target(
            name: "CleanerCore",
            dependencies: ["CZlib"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "CleanerCoreTests",
            dependencies: ["CleanerCore"]
        ),
    ]
)
