// swift-tools-version: 6.4

import Foundation
import PackageDescription

let qtPrefix = ProcessInfo.processInfo.environment["QT_PREFIX"] ?? "/opt/homebrew/opt/qtbase"
let qtHeaders = [
    "-F\(qtPrefix)/lib",
    "-I\(qtPrefix)/lib/QtCore.framework/Headers",
    "-I\(qtPrefix)/lib/QtGui.framework/Headers",
    "-I\(qtPrefix)/lib/QtCore.framework",
    "-I\(qtPrefix)/lib/QtGui.framework",
    "-I\(qtPrefix)/share/qt/mkspecs/macx-clang",
]

let package = Package(
    name: "GamaQt",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GamaQt", targets: ["GamaQt"]),
        .executable(name: "gama-qt-example", targets: ["GamaQtExample"]),
    ],
    dependencies: [.package(name: "Gama", path: "../..")],
    targets: [
        .target(
            name: "CGamaQtAdapter",
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("include"),
                .define("QT_CORE_LIB"),
                .define("QT_GUI_LIB"),
                .unsafeFlags(qtHeaders),
            ],
            linkerSettings: [
                .linkedFramework("QtCore"),
                .linkedFramework("QtGui"),
                .unsafeFlags(["-F\(qtPrefix)/lib", "-Xlinker", "-rpath", "-Xlinker", "\(qtPrefix)/lib"]),
            ]
        ),
        .target(
            name: "GamaQt",
            dependencies: [
                "CGamaQtAdapter",
                .product(name: "GamaCore", package: "Gama"),
                .product(name: "GamaDraw", package: "Gama"),
            ],
            swiftSettings: [
                .interoperabilityMode(.Cxx),
                .swiftLanguageMode(.v6),
                .unsafeFlags(qtHeaders.flatMap { ["-Xcc", $0] }),
            ]
        ),
        .testTarget(
            name: "GamaQtTests",
            dependencies: ["GamaQt", "CGamaQtAdapter", .product(name: "GamaCore", package: "Gama")],
            swiftSettings: [
                .interoperabilityMode(.Cxx),
                .swiftLanguageMode(.v6),
                .unsafeFlags(qtHeaders.flatMap { ["-Xcc", $0] }),
            ]
        ),
        .executableTarget(
            name: "GamaQtExample",
            dependencies: ["GamaQt", .product(name: "GamaCore", package: "Gama")],
            swiftSettings: [
                .interoperabilityMode(.Cxx),
                .swiftLanguageMode(.v6),
                .unsafeFlags(qtHeaders.flatMap { ["-Xcc", $0] }),
            ]
        ),
    ],
    cxxLanguageStandard: .cxx2b
)
