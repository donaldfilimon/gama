// swift-tools-version: 6.4
// Tools-version stays 6.4 deliberately: nothing here needs 6.5 manifest grammar,
// and Xcode's integrated SwiftPM (6.4) must still resolve this package for the
// xcodebuild platform gates. The COMPILER is the 6.5-dev snapshot via .swift-version.
import CompilerPluginSupport
import PackageDescription

let strictCore: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("ExistentialAny"),
    // SE-0444: members are visible only in files that import their module.
    // GamaCore is stdlib-only, so this is a conservative 6.5-dev hygiene flag.
    .enableUpcomingFeature("MemberImportVisibility"),
]

// @_extern(wasm) is still experimental — scoped to the WASM target only.
let wasmSettings: [SwiftSetting] = strictCore + [
    .enableExperimentalFeature("Extern")
]

let package = Package(
    name: "Gama",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17), .visionOS(.v1)],
    products: [
        .library(name: "Gama", targets: ["Gama"]),
        .library(name: "GamaCore", targets: ["GamaCore"]),
        .library(name: "GamaPlugin", targets: ["GamaPlugin"]),
        .library(name: "GamaPlatformServices", targets: ["GamaPlatformServices"]),
        .library(name: "GamaMacros", targets: ["GamaMacros"]),
        .library(name: "GamaDraw", targets: ["GamaDraw"]),
        .library(name: "GamaTUI", targets: ["GamaTUI"]),
        .library(name: "GamaWASM", targets: ["GamaWASM"]),
        .library(name: "GamaAppleUI", targets: ["GamaAppleUI"]),
        .library(name: "GamaAppleShell", targets: ["GamaAppleShell"]),
        // Static so the C entry points fold into the host binary/.so.
        .library(name: "GamaEmbed", type: .static, targets: ["GamaEmbed", "GamaEmbedABI"]),
        .library(name: "GamaMLIR", targets: ["GamaMLIR"]),
        .library(name: "GamaAndroidDemo", type: .dynamic, targets: ["GamaAndroidDemo"]),
        .executable(name: "gama-demo", targets: ["GamaDemo"]),
        .executable(name: "gama-web-demo", targets: ["GamaWebDemo"]),
        .executable(name: "gama-apple-demo", targets: ["GamaAppleDemo"]),
        .executable(name: "gama-windows-console-smoke", targets: ["GamaWindowsConsoleSmoke"]),
    ],
    dependencies: [
        // Build-time ONLY: macro plugins execute on the host compiler.
        // Nothing from swift-syntax links into shipped products, so the
        // zero-runtime-dependency constraint holds.
        .package(
            url: "https://github.com/swiftlang/swift-syntax.git",
            revision: "050f1a346fbbac0ca2cfb15a95274f7bd1cf0ccf"
        )
    ],
    targets: [
        .target(
            name: "Gama",
            dependencies: ["GamaCore"],
            path: "Sources/gama",
            swiftSettings: strictCore
        ),
        // ── Core: Embedded-Swift-safe. No Foundation. No existential
        //    views in hot paths. No weak refs. Pure value render IR.
        //    Owns FrameHost — the backend-shared event/focus engine.
        .target(name: "GamaCore", swiftSettings: strictCore),

        // ── Plugin runtime: Tier-1 capability model (manifest, grants,
        //    unforgeable handles, per-host PluginRuntime, PluginSlot).
        //    Stdlib-only like GamaCore; interfaces only — service
        //    implementations live in GamaPlatformServices or the app.
        .target(
            name: "GamaPlugin",
            dependencies: ["GamaCore"],
            swiftSettings: strictCore
        ),

        // ── Platform-conditional HostServices implementations (stderr
        //    log, monotonic clock, real scoped filesystem). May import
        //    Foundation; never imported by any portable target — the
        //    inverse grep in check-boundaries.sh enforces it.
        .target(
            name: "GamaPlatformServices",
            dependencies: ["GamaCore", "GamaPlugin"],
            swiftSettings: strictCore
        ),

        // ── Macro declarations (what user code imports)
        .target(
            name: "GamaMacros",
            dependencies: ["GamaCore", "GamaMacrosImpl"],
            swiftSettings: strictCore
        ),

        // ── Macro implementations (host-side compiler plugin)
        .macro(
            name: "GamaMacrosImpl",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ],
            swiftSettings: strictCore
        ),

        // ── Draw: platform-free rasterizer shared by every backend —
        //    CellBuffer (double-buffered grid + ANSI diff), CellPainter
        //    (IR → cells), DrawList (cells → vector commands + binary).
        .target(
            name: "GamaDraw",
            dependencies: ["GamaCore"],
            swiftSettings: strictCore
        ),

        // ── TUI backend: POSIX terminals (Darwin/Glibc — termios/ioctl
        //    import cleanly) and Windows Console (WinSDK — VT output,
        //    ReadConsoleInputW input). One Renderer, three OS families.
        .target(
            name: "GamaTUI",
            dependencies: ["GamaCore", "GamaDraw"],
            swiftSettings: strictCore
        ),

        // ── WASM backend: browser reactor. Compiles to inert stubs off
        //    wasm32; build with the pinned WASM Swift SDK in Toolchains.toml.
        .target(
            name: "GamaWASM",
            dependencies: ["GamaCore", "GamaDraw"],
            swiftSettings: wasmSettings
        ),

        // ── Apple GUI backend: NSView/UIView host drawing the DrawList
        //    via CoreGraphics. macOS, iOS, iPadOS, tvOS, visionOS.
        .target(
            name: "GamaAppleUI",
            dependencies: ["GamaCore", "GamaDraw"],
            swiftSettings: strictCore + [
                .enableUpcomingFeature("InferIsolatedConformances"),
            ]
        ),

        // macOS application ownership: NSApplication, NSWindow, lifecycle,
        // and per-shell window command routing. The source compiles to an
        // inert target when AppKit is unavailable.
        .target(
            name: "GamaAppleShell",
            dependencies: ["GamaCore", "GamaDraw", "GamaAppleUI"],
            swiftSettings: strictCore
        ),

        // ── Embed backend: flat C ABI (events in, DrawList bytes out)
        //    for Android/NDK, game engines, and non-Swift hosts.
        .target(
            name: "GamaEmbed",
            dependencies: ["GamaCore", "GamaDraw", "GamaEmbedABI"],
            swiftSettings: strictCore
        ),
        .target(
            name: "GamaEmbedABI",
            publicHeadersPath: "include"
        ),

        // ── MLIR lowering: RenderNode IR → `gama` dialect text.
        //    Embedded-safe (String building only).
        .target(
            name: "GamaMLIR",
            dependencies: ["GamaCore"],
            swiftSettings: strictCore
        ),

        // Sample-only Android shared library. JNI and Gradle remain under
        // Examples/Android and never enter the portable framework targets.
        .target(
            name: "GamaAndroidDemo",
            dependencies: ["GamaCore", "GamaEmbed"],
            path: "Examples/Android",
            exclude: ["app", "build.gradle.kts", "settings.gradle.kts", "gradle.properties"],
            sources: ["AndroidDemoBootstrap.swift"],
            swiftSettings: strictCore
        ),

        .executableTarget(
            name: "GamaDemo",
            dependencies: ["GamaCore", "GamaMacros", "GamaTUI", "GamaMLIR"],
            swiftSettings: strictCore
        ),
        // strictCore, not wasmSettings: the demo has no @_extern of its own,
        // and the experimental Extern feature stays scoped to GamaWASM.
        .executableTarget(
            name: "GamaWebDemo",
            dependencies: ["GamaCore", "GamaWASM"],
            swiftSettings: strictCore
        ),
        .executableTarget(
            name: "GamaAppleDemo",
            dependencies: ["GamaCore", "GamaAppleShell"],
            swiftSettings: strictCore
        ),
        .executableTarget(
            name: "GamaWindowsConsoleSmoke",
            dependencies: ["GamaTUI"],
            swiftSettings: strictCore
        ),

        .testTarget(
            name: "GamaTests",
            dependencies: [
                "Gama", "GamaCore", "GamaPlugin", "GamaPlatformServices",
                "GamaMacros", "GamaMLIR",
                "GamaTUI", "GamaDraw", "GamaEmbed", "GamaMacrosImpl",
                "GamaAppleUI", "GamaAppleShell", "GamaWASM",
                .product(name: "SwiftSyntaxMacroExpansion", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacrosGenericTestSupport", package: "swift-syntax")
            ],
            path: "Tests/gamaTests",
            swiftSettings: strictCore
        ),
    ]
)
