# Gama Agent Guide

## Repository Identity

- This is the SwiftPM Gama Framework checkout. `~/dev/active/gama-qt` is an unrelated Qt browser app.
- The package is a retained UI core plus plugin, drawing, TUI, Apple, WASM, C/Android, MLIR, macro, and demo targets.

## Toolchain And Commands

- Run `unset TOOLCHAINS` before Swift commands. Use `swiftly run swift ...`; `.swift-version` pins `main-snapshot-2026-08-21` (Swift 6.5-dev).
- `Package.swift` deliberately stays `swift-tools-version: 6.4` so Xcode's SwiftPM can resolve platform gates. `check-boundaries.sh` enforces this; do not upgrade it with the compiler.
- `Toolchains.toml` is the pin authority. `scripts/check-toolchain-pins.sh`, chained from the boundary gate, rejects drift in compiler/SDK revisions, URLs, and checksums.
- This checkout is iCloud/FileProvider-managed. Direct tests must use a scratch path outside the repository:

```bash
unset TOOLCHAINS
swiftly run swift --version # must report 6.5-dev
swiftly run swift build
swiftly run swift test --scratch-path /private/tmp/gama-framework-swiftpm
swiftly run swift test --scratch-path /private/tmp/gama-framework-swiftpm --filter SceneGraphTests
swiftly run swift build --target GamaCore
swiftly run swift run gama-demo
```

- Test filters match Swift source identifiers, not `@Suite` display names.
- Tests use Swift Testing (`import Testing`) only. Do not add XCTest; macro expansion tests use `SwiftSyntaxMacrosGenericTestSupport`.

## Verification

- Fast Apple gate: `./scripts/check-apple.sh` (debug build, all tests, release build).
- Portable ownership/import/symbol rules: `./scripts/check-boundaries.sh`.
- Documentation gates: `./scripts/check-docs.sh && ./scripts/check-doc-coverage.sh`. New public declarations need `///`; do not expand the coverage allowlist without a genuine baseline exception.
- Android cross-build/JNI packaging requires `ANDROID_NDK_HOME=... ./scripts/check-android.sh`.
- Full acceptance is `./scripts/check.sh`. Its `gates` array is authoritative and currently runs 13 fail-closed gates: Apple, Apple platforms, boundaries, concurrency negatives, C ABI, Embedded, Linux, WASM, Android, Android emulator, MLIR, DocC, and doc coverage.
- Some full-matrix gates require pinned SDKs, the NDK, Node/browser tooling, MLIR, or hosted non-macOS runners. Missing proof is a failure; do not weaken or skip gates to make the matrix green.
- CI truth is `.github/workflows/ci.yml`. Windows deliberately uses the pinned Swift 6.4.x exception; other jobs use the 6.5-dev snapshot family.

## Architecture Boundaries

- Flow: `App -> SceneBuilder -> RenderNode -> LayoutEngine -> CellPainter -> CellBuffer -> DrawList -> backend`; platform events return through `FrameHost`.
- Every app declares exactly one primary scene. All backends except `GamaAppleShell` render only that primary scene; the shell owns macOS auxiliary/multi-window surfaces.
- `GamaCore` and `GamaPlugin` are stdlib-only. They may not import Foundation, platform UI/POSIX modules, WinSDK, or Synchronization, and framework state must not move into process-global registries.
- `FrameHost` and `AppRuntime` are `~Copyable`; each host uniquely owns focus, actions, subscriptions, dirty state, and frames. Out-of-band changes use host subscriptions or explicit `invalidate()`.
- `GamaPlatformServices` contains Foundation-backed host-service implementations. Only apps, demos, examples, and tests may import it; portable/framework targets must depend on service interfaces instead.
- `GamaMacrosImpl` is a host compiler plugin. `swift-syntax` is revision-pinned and build-time-only; shipped products must retain zero runtime package dependencies.
- Backends translate events and present shared `DrawList` output; do not fork layout, paint, or application semantics. Keep C `gama_embed_v1_*` and WASM `gama_web_v1_*` symbols versioned and separately namespaced.

## State And Documentation Traps

- Scene content closures run every frame. A component constructed inline loses its instance-backed `@Reactive` state; hoist intentionally persistent component instances as in `Sources/GamaDemo/main.swift`.
- Hoisted state in a `WindowGroup` is shared across its surfaces. There is no framework-provided per-window component storage yet.
- Read `docs/README.md`, the relevant `docs/adr/` record, and `docs/backends/<Backend>.md` before changing a settled backend contract. Plugin tier/capability work starts with `docs/Plugins.md`.
- `docs/Capabilities.md` is the evidence ledger. Distinguish implemented, locally proven, hosted proven, provisional, and blocked behavior; implementation presence alone is not platform proof.

## Repository Safety

- Preserve `Package.resolved`. Never commit credentials or runner configuration, force-push `main`, or merge before required checks are green.
- Never run `git gc`, `git prune`, `git fsck`, or `git repack` in this FileProvider-managed checkout.
