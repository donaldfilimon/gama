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
        .library(name: "GamaUSD", targets: ["GamaUSD"]),
        .library(name: "GamaConsole", targets: ["GamaConsole"]),
        .library(name: "GamaGraph", targets: ["GamaGraph"]),
    ],
    dependencies: [
        // PR #108's head: the native-region API the viewport needs.
        .package(url: "https://github.com/donaldfilimon/gama.git", revision: "2ef325c120674cfe218de44f492f435ff50a28e7"),
    ],
    targets: [
        // Standard library only: tools/check.sh rejects platform imports here.
        .target(name: "GamaAuthoring", swiftSettings: strictLibrary),
        // USDA save and load (ADR 0005). Standard library only, like
        // GamaAuthoring: tools/check.sh bans platform imports here too.
        .target(
            name: "GamaUSD",
            dependencies: ["GamaAuthoring"],
            swiftSettings: strictLibrary
        ),
        .testTarget(
            name: "GamaUSDTests",
            dependencies: ["GamaUSD", "GamaAuthoring"],
            exclude: ["Fixtures"],
            swiftSettings: strictCore
        ),
        // Graph evaluation (ADR 0007): node definitions, the standard node
        // set, and the evaluator whose output nodes emit ordinary
        // DocumentCommands. Standard library only, like GamaAuthoring.
        .target(
            name: "GamaGraph",
            dependencies: ["GamaAuthoring"],
            swiftSettings: strictLibrary
        ),
        .testTarget(
            name: "GamaGraphTests",
            dependencies: ["GamaGraph", "GamaAuthoring"],
            swiftSettings: strictCore
        ),
        // The command console's parser (ADR 0006): text in, the same
        // DocumentCommands every other surface produces out. Standard
        // library only; tools/check.sh bans platform imports here too.
        .target(
            name: "GamaConsole",
            dependencies: ["GamaAuthoring", "GamaGraph"],
            swiftSettings: strictLibrary
        ),
        .testTarget(
            name: "GamaConsoleTests",
            dependencies: ["GamaConsole", "GamaAuthoring", "GamaGraph"],
            swiftSettings: strictCore
        ),
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
                "GamaUSD",
                "GamaConsole",
                "GamaGraph",
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
                "GamaUSD",
                "GamaGraph",
                // StudioAppTests drives a FrameHost and paints its frames to
                // text, which needs both gama modules imported directly.
                .product(name: "GamaCore", package: "gama"),
                .product(name: "GamaDraw", package: "gama"),
                // ViewportTests attaches the ARView to a real GamaHostView.
                .product(name: "GamaAppleUI", package: "gama"),
            ],
            swiftSettings: strictCore
        ),
        // Native window stub: AppKit host loop around GamaStudioEditor.
        .executableTarget(
            name: "gama-studio",
            dependencies: [
                "GamaStudioEditor",
                // --smoke compares the bridge against the document, and
                // MemberImportVisibility needs each defining module imported.
                "GamaAuthoring",
                "GamaReality",
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
