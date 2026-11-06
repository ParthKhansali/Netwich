// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MergeKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MergeKit", targets: ["MergeKit"]),
        .executable(name: "mergecli", targets: ["mergecli"]),
    ],
    targets: [
        // Language mode v5 while the network hot paths use lock-guarded classes;
        // migrate to v6 once the provider pump is settled.
        .target(
            name: "MergeKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "mergecli",
            dependencies: ["MergeKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "MergeKitTests",
            dependencies: ["MergeKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
