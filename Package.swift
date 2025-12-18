// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "gama",
    products: [
        .library(name: "Gama", targets: ["Gama"]),
        .executable(name: "gama-demo", targets: ["GamaDemo"])
    ],
    dependencies: [
        // Swift 6.2 macro support (when available)
    ],
    targets: [
        .target(
            name: "Gama",
            dependencies: [],
            path: "Sources/Gama",
            exclude: ["Gama.swift", "PLATFORM_SUPPORT.md"],
            swiftSettings: [
                .enableUpcomingFeature("BareSlashRegexLiterals"),
                .enableUpcomingFeature("ConciseMagicFile"),
                .enableUpcomingFeature("ForwardTrailingClosures"),
                .enableUpcomingFeature("ImplicitOpenExistentials"),
                .enableUpcomingFeature("StrictConcurrency"),
                .enableUpcomingFeature("RegionBasedIsolation"),
                .enableExperimentalFeature("VariadicGenerics"),
                .enableExperimentalFeature("NonescapableTypes"),
                .enableExperimentalFeature("NoncopyableGenerics"),
                .enableExperimentalFeature("GlobalConcurrency"),
                .enableExperimentalFeature("TypedThrows")
            ]
        ),
        .executableTarget(
            name: "GamaDemo",
            dependencies: ["Gama"],
            path: "Sources/Gama",
            sources: ["Gama.swift"],
            swiftSettings: [
                .enableUpcomingFeature("BareSlashRegexLiterals"),
                .enableUpcomingFeature("ConciseMagicFile"),
                .enableUpcomingFeature("ForwardTrailingClosures"),
                .enableUpcomingFeature("ImplicitOpenExistentials"),
                .enableUpcomingFeature("StrictConcurrency"),
                .enableUpcomingFeature("RegionBasedIsolation"),
                .enableExperimentalFeature("VariadicGenerics"),
                .enableExperimentalFeature("NonescapableTypes"),
                .enableExperimentalFeature("NoncopyableGenerics"),
                .enableExperimentalFeature("GlobalConcurrency"),
                .enableExperimentalFeature("TypedThrows")
            ]
        ),
        .testTarget(
            name: "GamaTests",
            dependencies: ["Gama"],
            path: "Tests/GamaTests",
            swiftSettings: [
                .enableUpcomingFeature("BareSlashRegexLiterals"),
                .enableUpcomingFeature("ConciseMagicFile"),
                .enableUpcomingFeature("ForwardTrailingClosures"),
                .enableUpcomingFeature("ImplicitOpenExistentials"),
                .enableUpcomingFeature("StrictConcurrency"),
                .enableUpcomingFeature("RegionBasedIsolation"),
                .enableExperimentalFeature("VariadicGenerics"),
                .enableExperimentalFeature("NonescapableTypes"),
                .enableExperimentalFeature("NoncopyableGenerics"),
                .enableExperimentalFeature("GlobalConcurrency"),
                .enableExperimentalFeature("TypedThrows")
            ]
        )
    ]
)