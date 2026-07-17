// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TortoiseBlocksKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
        .visionOS(.v26),
    ],
    products: [
        .library(name: "TortoiseBlocksKit", targets: ["TortoiseBlocksKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/temoki/TortoiseGraphics2", exact: "2.0.0-beta8")
    ],
    targets: [
        .target(
            name: "TortoiseBlocksKit",
            dependencies: [
                .product(name: "TortoiseCore", package: "TortoiseGraphics2")
            ]
        ),
        .testTarget(
            name: "TortoiseBlocksKitTests",
            dependencies: ["TortoiseBlocksKit"]
        ),
    ]
)
