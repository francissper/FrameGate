// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FrameGateCore",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "FrameGateCore", targets: ["FrameGateCore"])
    ],
    targets: [
        .target(name: "FrameGateCore"),
        .testTarget(
            name: "FrameGateCoreTests",
            dependencies: ["FrameGateCore"],
            resources: [.copy("Fixtures")]
        )
    ]
)
