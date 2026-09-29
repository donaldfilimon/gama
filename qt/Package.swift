// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.
// Built with Xcode Swift 6.4; C++23 via `.cxx2b`. Safe Cxx bridging targets Swift 6 concurrency.

import Foundation
import PackageDescription

/// Homebrew Qt prefix. Override with `QT_PREFIX` (e.g. `/opt/homebrew/opt/qtbase`).
let qtPrefix = ProcessInfo.processInfo.environment["QT_PREFIX"] ?? "/opt/homebrew"

let cxxInteropSettings: [SwiftSetting] = [
    .interoperabilityMode(.Cxx),
    .enableUpcomingFeature("ApproachableConcurrency"),
    .enableUpcomingFeature("MemberImportVisibility"),
]

let qtFrameworkSearch = [
    "-F\(qtPrefix)/lib",
]

let qtHeaderFlags = [
    "-F\(qtPrefix)/lib",
    "-I\(qtPrefix)/lib/QtCore.framework/Headers",
    "-I\(qtPrefix)/lib/QtGui.framework/Headers",
    "-I\(qtPrefix)/lib/QtWidgets.framework/Headers",
    "-I\(qtPrefix)/lib/QtNetwork.framework/Headers",
    "-I\(qtPrefix)/lib/QtCore.framework",
    "-I\(qtPrefix)/lib/QtGui.framework",
    "-I\(qtPrefix)/lib/QtWidgets.framework",
    "-I\(qtPrefix)/lib/QtNetwork.framework",
    "-I\(qtPrefix)/share/qt/mkspecs/macx-clang",
    "-I\(qtPrefix)/include",
]

let qtFrameworks: [LinkerSetting] = [
    .linkedFramework("QtCore"),
    .linkedFramework("QtGui"),
    .linkedFramework("QtWidgets"),
    .linkedFramework("QtNetwork"),
    .linkedFramework("JavaScriptCore"),
    .unsafeFlags(qtFrameworkSearch),
]

let qtRuntimeRpath: [LinkerSetting] = [
    .unsafeFlags(
        qtFrameworkSearch + [
            "-Xlinker", "-rpath",
            "-Xlinker", "\(qtPrefix)/lib",
        ]
    ),
]

let package = Package(
    name: "Gama",
    platforms: [
        .macOS(.v27), // Liquid Glass + FoundationModels (CoreAI search)
    ],
    products: [
        .executable(name: "Gama", targets: ["Gama"]),
        .library(name: "GamaCore", targets: ["GamaCore"]),
    ],
    dependencies: [],
    targets: [
        // Pure Swift helpers (address resolution) — no Qt / Cxx.
        .target(
            name: "GamaCore",
            path: "Sources/GamaCore",
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
                .enableUpcomingFeature("MemberImportVisibility"),
            ]
        ),
        // Header-only Qt/C++: detail/*.hpp holds implementations; include/GamaQt.hpp
        // is the Swift-facing clang module (declarations only). CGamaQt.cpp is the
        // SPM-required stub that includes the detail headers.
        .target(
            name: "CGamaQt",
            path: "Sources/CGamaQt",
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("include"),
                .headerSearchPath("detail"),
                .define("QT_CORE_LIB"),
                .define("QT_GUI_LIB"),
                .define("QT_WIDGETS_LIB"),
                .define("QT_NETWORK_LIB"),
                .unsafeFlags(qtHeaderFlags),
            ],
            linkerSettings: qtFrameworks
        ),
        .executableTarget(
            name: "Gama",
            dependencies: [
                "CGamaQt",
                "GamaCore",
            ],
            path: "Sources/Gama",
            swiftSettings: cxxInteropSettings,
            linkerSettings: qtRuntimeRpath
        ),
        .testTarget(
            name: "GamaTests",
            dependencies: ["CGamaQt", "GamaCore"],
            path: "Tests/GamaTests",
            swiftSettings: cxxInteropSettings,
            linkerSettings: qtRuntimeRpath
        ),
    ],
    swiftLanguageModes: [.v6],
    cxxLanguageStandard: .cxx2b
)
