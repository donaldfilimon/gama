# Platform setup and limitations

Interpret platform support from executed evidence, not source presence.

## Toolchains

Apple, Linux, static Linux, WebAssembly, Android, and Embedded checks all use
the exact August 21, 2026 Swift 6.5-dev main development snapshot (toolchain id
`org.swift.65202608211a`) with `TOOLCHAINS` unset, plus the matching Swift SDK
artifact bundles. The xcodebuild iOS/tvOS/visionOS gates are the one exception
and use Xcode's default Apple Swift 6.4 toolchain, which is why the manifest
stays `swift-tools-version: 6.4`. Windows is a second, deliberate exception:
swift.org has published no Windows main-development snapshot since May 20,
2026, so that job stays on the proven `release/6.4.x` August 14, 2026 snapshot
and is not verified on 6.5-dev. URLs, revisions, IDs, and SHA-256 values are
pinned in `Toolchains.toml`. Everyday builds use `swiftly run` (see
`docs/Toolchain.md`). Tests are Swift Testing only (`docs/Testing.md`).
`scripts/check-toolchain-pins.sh` fails if CI or check-script defaults
drift from `Toolchains.toml`.

The dated Android Swift runtime requires the libc++ ABI in Android NDK
30.0.15729638 (an NDK 30 release candidate). That revision is pinned across the
manifest, Gradle sample, local setup, and CI; older NDK 27/28 libraries fail the
runtime symbol gate and are not accepted.

## Evidence boundaries

Embedded Swift is experimental. Gama's Embedded claim means the unchanged
portable core compiled and linked as a whole-module artifact with recorded
size; it is not hardware certification. `GamaMLIR` emits deterministic textual
generic-form custom operations that parse with unregistered dialects enabled;
it is not a Swift compiler frontend.

Cross-compilation does not prove a native runtime. Android has a local arm64
emulator input/frame proof but still requires its hosted x86_64 emulator job.
Windows console behavior becomes current only after its native hosted job
passes. The evidence table in `docs/Capabilities.md` is the status authority.
