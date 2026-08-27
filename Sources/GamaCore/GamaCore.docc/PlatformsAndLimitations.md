# Platform setup and limitations

Interpret platform support from executed evidence, not source presence.

## Toolchains

Apple builds use Xcode's default Apple Swift 6.4 toolchain with `TOOLCHAINS`
unset. Linux, static Linux, WebAssembly, Android, and Embedded checks use the
exact August 14, 2026 `release/6.4.x` development snapshot and matching Swift
SDK artifact bundles. URLs, revisions, IDs, and SHA-256 values are pinned in
`Toolchains.toml`.

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
