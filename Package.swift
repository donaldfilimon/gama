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
    // macOS 15 / iOS 18 / tvOS 26 is RealityKit's floor for cone and cylinder
    // meshes (ADR 0002); every Primitive must map to a real mesh.
    platforms: [.macOS(.v15), .iOS(.v18), .tvOS(.v26), .visionOS(.v1)],
    products: [
        .library(name: "GamaAuthoring", targets: ["GamaAuthoring"]),
        .library(name: "GamaReality", targets: ["GamaReality"]),
    ],
    dependencies: [
        // PR #108's head: the native-region API the viewport needs.
        .package(url: "https://github.com/donaldfilimon/gama.git", revision: "2ef325c120674cfe218de44f492f435ff50a28e7"),
    ],
    targets: [
        // Standard library only: tools/check.sh rejects platform imports here.
        .target(name: "GamaAuthoring", swiftSettings: strictLibrary),
        // Apple-only runtime projection; compiles to nothing without RealityKit.
        .target(
            name: "GamaReality",
            dependencies: ["GamaAuthoring"],
            swiftSettings: strictLibrary
        ),
        .testTarget(
            name: "GamaAuthoringTests",
            dependencies: ["GamaAuthoring"],
            swiftSettings: strictCore
        ),
        .testTarget(
            name: "GamaRealityTests",
            dependencies: ["GamaAuthoring", "GamaReality"],
            swiftSettings: strictCore
        ),
        // Wraps the authoring/reality model in a gama App/Window so it can
        // be hosted by GamaAppleUI's GamaHostView.
        .target(
            name: "GamaStudioEditor",
            dependencies: [
                "GamaAuthoring",
                "GamaReality",
                .product(name: "GamaCore", package: "gama"),
                .product(name: "GamaAppleUI", package: "gama"),
            ],
            swiftSettings: strictLibrary
        ),
        .testTarget(
            name: "GamaStudioEditorTests",
            dependencies: [
                "GamaStudioEditor",
                "GamaAuthoring",
                "GamaReality",
                // StudioAppTests drives a FrameHost and paints its frames to
                // text, which needs both gama modules imported directly.
                .product(name: "GamaCore", package: "gama"),
                .product(name: "GamaDraw", package: "gama"),
            ],
            swiftSettings: strictCore
        ),
        // Native window stub: AppKit host loop around GamaStudioEditor.
        .executableTarget(
            name: "gama-studio",
            dependencies: [
                "GamaStudioEditor",
                .product(name: "GamaAppleUI", package: "gama"),
                .product(name: "GamaCore", package: "gama"),
                // MemberImportVisibility requires importing DrawList's
                // defining module directly to read `currentDrawList.commands`
                // in the --smoke check, even though GamaAppleUI re-exports it.
                .product(name: "GamaDraw", package: "gama"),
            ],
            swiftSettings: strictCore
        ),
    ]
)
