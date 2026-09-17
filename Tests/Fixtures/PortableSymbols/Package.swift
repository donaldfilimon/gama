// swift-tools-version: 6.4
import PackageDescription

// Standalone negative fixture package. It is intentionally not a dependency
// of Gama's root package; scripts/check-linux.sh cross-compiles it only to
// prove that the portable-symbol scanner rejects its emitted object.
let package = Package(
    name: "GamaPortableSymbolFixtures",
    targets: [
        .target(name: "RoundedRequiresLibm"),
    ]
)
