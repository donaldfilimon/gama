// swift-tools-version: 6.4
// Tools-version matches gama's deliberately: a later dependency on
// donaldfilimon/gama needs no manifest or toolchain change. The COMPILER is the
// 6.5-dev snapshot pinned in .swift-version, the same pin gama uses.
import PackageDescription

let strictCore: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("InternalImportsByDefault"),
]

// Shipped library targets additionally build under strict memory safety with
// the diagnostic group promoted to an error, mirroring gama's `strictLibrary`.
let strictLibrary: [SwiftSetting] = strictCore + [
    .strictMemorySafety(),
    .treatWarning("StrictMemorySafety", as: .error),
]

let package = Package(
    name: "GamaStudio",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17), .visionOS(.v1)],
    products: [
        .library(name: "GamaAuthoring", targets: ["GamaAuthoring"]),
    ],
    targets: [
        // Standard library only: tools/check.sh rejects platform imports here.
        .target(name: "GamaAuthoring", swiftSettings: strictLibrary),
        .testTarget(
            name: "GamaAuthoringTests",
            dependencies: ["GamaAuthoring"],
            swiftSettings: strictCore
        ),
    ]
)
