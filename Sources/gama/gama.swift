/// Umbrella module: re-exports the portable core so `import Gama` gives an
/// application the full view/state/layout surface with one import. Pick a
/// backend product (`GamaTUI`, `GamaAppleUI`, `GamaWASM`, `GamaEmbed`) to
/// present frames.
@_exported import GamaCore
