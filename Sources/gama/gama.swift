/// Umbrella module: re-exports the portable core so `import Gama` gives an
/// application the full view/state/layout surface with one import. Pick a
/// backend product (`GamaTUI`, `GamaAppleUI`, `GamaWASM`, `GamaEmbed`) to
/// present frames.
@_exported import GamaCore

/// Returns and prints the original Gama package greeting.
///
/// This compatibility API remains available for clients of the initial
/// scaffold. New applications should build a `GamaCore.App` and choose a
/// renderer product such as `GamaTUI` or `GamaAppleUI`.
@available(*, deprecated, message: "Build a GamaCore.App and select a renderer backend")
public func hello() -> String {
    let message = "Hello, world!"
    print(message)
    return message
}
