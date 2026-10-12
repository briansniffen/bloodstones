// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BloodstonesEngine",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "BloodstonesEngine", targets: ["BloodstonesEngine"]),
        .executable(name: "bloodstones", targets: ["BloodstonesCLI"]),
    ],
    targets: [
        .target(name: "BloodstonesEngine"),
        .executableTarget(name: "BloodstonesCLI", dependencies: ["BloodstonesEngine"]),
        .testTarget(name: "BloodstonesEngineTests", dependencies: ["BloodstonesEngine"]),
    ]
)
