// swift-tools-version: 6.0
// This is a Skip (https://skip.dev) package.
import PackageDescription

let package = Package(
    name: "tune-out",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14), .tvOS(.v17), .watchOS(.v10), .macCatalyst(.v17)],
    products: [
        .library(name: "TuneOut", type: .dynamic, targets: ["TuneOut"]),
        .library(name: "TuneOutModel", type: .dynamic, targets: ["TuneOutModel"]),
    ],
    dependencies: [
        .package(url: "https://source.skip.tools/skip.git", from: "1.6.13"),
        .package(url: "https://source.skip.tools/skip-ui.git", from: "1.39.0"),
        .package(url: "https://source.skip.tools/skip-foundation.git", from: "1.3.9"),
        .package(url: "https://source.skip.tools/skip-model.git", from: "1.6.0"),
        .package(url: "https://source.skip.tools/skip-av.git", "0.5.3"..<"2.0.0"),
        .package(url: "https://source.skip.tools/skip-sql.git", "0.12.0"..<"2.0.0"),
        .package(url: "https://source.skip.tools/skip-marketplace.git", "0.0.0"..<"2.0.0"),
        .package(url: "https://github.com/appfair/appfair-app.git", from: "1.0.0"),
    ],
    targets: [
        .target(name: "TuneOut", dependencies: [
            "TuneOutModel",
            .product(name: "AppFairUI", package: "appfair-app"),
            .product(name: "SkipUI", package: "skip-ui"),
            .product(name: "SkipMarketplace", package: "skip-marketplace"),
        ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
        .testTarget(name: "TuneOutTests", dependencies: [
            "TuneOut",
            .product(name: "SkipTest", package: "skip")
        ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
        .target(name: "TuneOutModel", dependencies: [
            .product(name: "SkipFoundation", package: "skip-foundation"),
            .product(name: "SkipModel", package: "skip-model"),
            .product(name: "SkipAV", package: "skip-av"),
            .product(name: "SkipSQL", package: "skip-sql"),
        ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
        .testTarget(name: "TuneOutModelTests", dependencies: [
            "TuneOutModel",
            .product(name: "SkipTest", package: "skip")
        ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
    ]
)
