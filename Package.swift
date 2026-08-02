// swift-tools-version: 6.0
import PackageDescription

// CAVOK Compatibility Check — a standalone probe app handed to volunteer testers
// so we can learn whether CAVOK's real engine (MLX on Metal) runs on macOS
// versions we don't own a machine for.
//
// The deployment target here is the WHOLE POINT: 14.0 is the floor every CAVOK
// dependency actually declares (mlx-swift 14.0, swift-transformers 13.0). If
// this package fails to build at 14.0, that is the answer to "can CAVOK drop to
// macOS 14" and we learned it without shipping anything.
//
// Deliberately does NOT depend on BloomRAG: that target imports FoundationModels
// (macOS 26-only) and would drag the pin right back in. This links mlx-swift
// directly.
let package = Package(
    name: "CavokCompat",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.25.6")
    ],
    targets: [
        .executableTarget(
            name: "CavokCompat",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXRandom", package: "mlx-swift")
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
