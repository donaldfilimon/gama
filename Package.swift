// swift-tools-version: 6.4

import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ApproachableConcurrency"),
    .swiftLanguageMode(.v6),
]

let package = Package(
    name: "gama",
    products: [
        .library(name: "GamaCore", targets: ["GamaCore"]),
        .library(name: "GamaTUI", targets: ["GamaTUI"]),
        .executable(name: "gama", targets: ["gama"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
    ],
    targets: [
        .target(name: "GamaCore", swiftSettings: swiftSettings),
        .target(name: "GamaTUI", dependencies: ["GamaCore"], swiftSettings: swiftSettings),
        .executableTarget(
            name: "gama",
            dependencies: [
                "GamaTUI",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(name: "GamaCoreTests", dependencies: ["GamaCore"], swiftSettings: swiftSettings),
        .testTarget(name: "GamaTUITests", dependencies: ["GamaTUI"], swiftSettings: swiftSettings),
        .testTarget(name: "gamaTests", dependencies: ["gama"], swiftSettings: swiftSettings),
    ]
)
