// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "gama",
    platforms: [
        .macOS(.v12),
        .iOS(.v15),
        .tvOS(.v15),
        .watchOS(.v8),
        .linux,
        .android  // When Swift supports it
    ],
    products: [
        .library(name: "Gama", targets: ["Gama"])
    ],
    dependencies: [
        // Linux: GTK4 Swift bindings
        .package(url: "https://github.com/stackotter/swift-cross-ui", from: "0.0.0"), // Placeholder - actual GTK bindings
    ],
    targets: [
        .executableTarget(
            name: "Gama",
            dependencies: []
        ),
        .target(
            name: "GamaLinux",
            dependencies: [
                // .product(name: "Gtk4", package: "swiftgtk4") // When available
            ],
            swiftSettings: [.define("PLATFORM_LINUX")]
        ),
        .target(
            name: "GamaApple",
            dependencies: [],
            swiftSettings: [.define("PLATFORM_APPLE")]
        ),
        .target(
            name: "GamaAndroid",
            dependencies: [],
            swiftSettings: [.define("PLATFORM_ANDROID")]
        )
    ]
)