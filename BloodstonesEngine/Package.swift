// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BloodstonesEngine",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "BloodstonesEngine", targets: ["BloodstonesEngine"]),
        .executable(name: "bloodstones", targets: ["BloodstonesCLI"]),
        .library(name: "BloodstonesUI", targets: ["BloodstonesUI"]),
    ],
    targets: [
        .target(name: "BloodstonesEngine"),
        .executableTarget(name: "BloodstonesCLI", dependencies: ["BloodstonesEngine"]),
        .testTarget(name: "BloodstonesEngineTests", dependencies: ["BloodstonesEngine"]),
        // SwiftUI screens and the view model; builds for iOS and macOS so the
        // views can be rendered to images on a Mac.
        .target(name: "BloodstonesUI", dependencies: ["BloodstonesEngine"]),
        .executableTarget(name: "BloodstonesSnapshot", dependencies: ["BloodstonesUI"]),
        .testTarget(name: "BloodstonesUITests", dependencies: ["BloodstonesUI"]),
    ]
)
