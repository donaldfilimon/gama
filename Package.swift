// swift-tools-version: 6.2

import PackageDescription
import CompilerPluginSupport

let sharedSwiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ApproachableConcurrency"),
]

let package = Package(
    name: "Gama",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
    ],
    products: [
        .library(name: "GamaCore", targets: ["GamaCore"]),
        .library(name: "GamaMetal", targets: ["GamaMetal"]),
        .library(name: "GamaVulkan", targets: ["GamaVulkan"]),
        .library(name: "GamaDX12", targets: ["GamaDX12"]),
        .library(name: "GamaMath", targets: ["GamaMath"]),
        .library(name: "GamaScene", targets: ["GamaScene"]),
        .library(name: "GamaUI", targets: ["GamaUI"]),
        .library(name: "GamaMacroDeclarations", targets: ["GamaMacroDeclarations"]),
        .executable(name: "GamaDemo", targets: ["GamaDemo"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.1"),
    ],
    targets: [
        // MARK: - Core Abstraction Layer
        .target(
            name: "GamaCore",
            swiftSettings: sharedSwiftSettings
        ),

        // MARK: - Metal Backend
        .target(
            name: "GamaMetal",
            dependencies: ["GamaCore"],
            swiftSettings: sharedSwiftSettings,
            linkerSettings: [
                .linkedFramework("Metal", .when(platforms: [.macOS, .iOS])),
                .linkedFramework("MetalKit", .when(platforms: [.macOS, .iOS])),
                .linkedFramework("QuartzCore", .when(platforms: [.macOS, .iOS])),
            ]
        ),

        // MARK: - Vulkan Backend (stubs)
        .target(
            name: "GamaVulkan",
            dependencies: ["GamaCore"],
            swiftSettings: sharedSwiftSettings
        ),

        // MARK: - DirectX 12 Backend (stubs)
        .target(
            name: "GamaDX12",
            dependencies: ["GamaCore"],
            swiftSettings: sharedSwiftSettings
        ),

        // MARK: - Math Library
        .target(
            name: "GamaMath",
            swiftSettings: sharedSwiftSettings
        ),

        // MARK: - Scene Graph
        .target(
            name: "GamaScene",
            dependencies: ["GamaCore"],
            swiftSettings: sharedSwiftSettings
        ),

        // MARK: - UI Framework
        .target(
            name: "GamaUI",
            swiftSettings: sharedSwiftSettings
        ),

        // MARK: - Macros
        .macro(
            name: "GamaMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ],
            swiftSettings: sharedSwiftSettings
        ),
        .target(
            name: "GamaMacroDeclarations",
            dependencies: ["GamaMacros"],
            swiftSettings: sharedSwiftSettings
        ),

        // MARK: - Demo CLI
        .executableTarget(
            name: "GamaDemo",
            dependencies: [
                "GamaCore",
                "GamaMetal",
                "GamaMacroDeclarations",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: sharedSwiftSettings,
            linkerSettings: [
                .linkedFramework("AppKit", .when(platforms: [.macOS])),
                .linkedFramework("QuartzCore", .when(platforms: [.macOS])),
            ]
        ),

        // MARK: - Tests
        .testTarget(
            name: "GamaCoreTests",
            dependencies: ["GamaCore"],
            swiftSettings: sharedSwiftSettings
        ),
        .testTarget(
            name: "GamaMetalTests",
            dependencies: ["GamaMetal", "GamaCore"],
            swiftSettings: sharedSwiftSettings
        ),
        .testTarget(
            name: "GamaMathTests",
            dependencies: ["GamaMath"],
            swiftSettings: sharedSwiftSettings
        ),
        .testTarget(
            name: "GamaSceneTests",
            dependencies: ["GamaScene"],
            swiftSettings: sharedSwiftSettings
        ),
        .testTarget(
            name: "GamaUITests",
            dependencies: ["GamaUI"],
            swiftSettings: sharedSwiftSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
