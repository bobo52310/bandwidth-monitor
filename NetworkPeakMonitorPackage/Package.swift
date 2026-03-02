// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "NetworkPeakMonitorFeature",
    platforms: [.macOS(.v14)], // macOS 14+ for @Observable macro and Swift Charts
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "NetworkPeakMonitorFeature",
            targets: ["NetworkPeakMonitorFeature"]
        ),
    ],
    dependencies: [
        // Add any external package dependencies here if needed
        // Swift Charts is built-in for macOS 13+
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "NetworkPeakMonitorFeature"
        ),
        .testTarget(
            name: "NetworkPeakMonitorFeatureTests",
            dependencies: [
                "NetworkPeakMonitorFeature"
            ]
        ),
    ]
)
