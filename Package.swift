// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "gama",
    platforms: [
        .macOS(.v12),
        .iOS(.v15),
        .tvOS(.v15),
        .watchOS(.v8)
    ],
    products: [
        .library(name: "Gama", targets: ["Gama"]),
        .executable(name: "gama-demo", targets: ["GamaDemo"])
    ],
    dependencies: [
        // Future dependencies for platform-specific bindings
    ],
    targets: [
        .target(
            name: "Gama",
            dependencies: [],
            path: "Sources/Gama",
            exclude: ["Gama.swift"]
        ),
        .executableTarget(
            name: "GamaDemo",
            dependencies: ["Gama"],
            path: "Sources/Gama",
            sources: ["Gama.swift"]
        )
    ]
)