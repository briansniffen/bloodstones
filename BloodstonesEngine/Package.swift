// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BloodstonesEngine",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "BloodstonesEngine", targets: ["BloodstonesEngine"]),
    ],
    targets: [
        .target(name: "BloodstonesEngine"),
        .testTarget(name: "BloodstonesEngineTests", dependencies: ["BloodstonesEngine"]),
    ]
)
