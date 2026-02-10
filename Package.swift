// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "IntersectionAhead",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "EngineAlpha",
            targets: ["EngineAlpha"]
        ),
        .executable(
            name: "RoadIndexCLI",
            targets: ["RoadIndexCLI"]
        )
    ],
    targets: [
        .target(
            name: "EngineAlpha"
        ),
        .executableTarget(
            name: "RoadIndexCLI",
            dependencies: ["EngineAlpha"],
            path: "Sources/RoadIndexCLI"
        ),
        .testTarget(
            name: "EngineAlphaTests",
            dependencies: ["EngineAlpha"]
        )
    ]
)
