# Gama Agent Guide

## Repository Identity

- This is the SwiftPM Gama Framework checkout. `~/dev/active/gama-qt` is an unrelated Qt browser app.
- The package is a retained UI core plus plugin, drawing, TUI, Apple, WASM, C/Android, MLIR, macro, and demo targets.

## Toolchain And Commands

- Run `unset TOOLCHAINS` before Swift commands. Use `swiftly run swift ...`; `.swift-version` pins `main-snapshot-2026-08-21` (Swift 6.5-dev).
- `Package.swift` deliberately stays `swift-tools-version: 6.4` so Xcode's SwiftPM can resolve platform gates. `check-boundaries.sh` enforces this; do not upgrade it with the compiler.
- `Toolchains.toml` is the pin authority. `scripts/check-toolchain-pins.sh`, chained from the boundary gate, rejects drift in compiler/SDK revisions, URLs, and checksums; it also discovers every `GAMA_TOOLCHAIN_ID` default rather than listing scripts, and fails on any checked-in home-directory path under `scripts/`.
- Scripts derive the pinned snapshot's location from `Toolchains.toml` through `scripts/lib/toolchain.sh`. Do not write an absolute toolchain path into a script; override with `GAMA_SWIFT_64` / `GAMA_SWIFTC_64` / `GAMA_EMBEDDED_TOOLCHAIN` instead.
- This checkout is iCloud/FileProvider-managed. Direct tests must use a scratch path outside the repository:

```bash
unset TOOLCHAINS
swiftly run swift --version # must report 6.5-dev
swiftly run swift build
swiftly run swift test --scratch-path /private/tmp/gama-framework-swiftpm
swiftly run swift test --scratch-path /private/tmp/gama-framework-swiftpm --filter SceneGraphTests
swiftly run swift build --target GamaCore
swiftly run swift run gama-demo
.agents/skills/run-gama/driver.sh smoke   # tmux-driven TUI proof; do not pipe gama-demo
```

- Test filters match Swift source identifiers, not `@Suite` display names. A non-matching filter prints a warning and exits 0; confirm the test count.
- Tests use Swift Testing (`import Testing`) only. Do not add XCTest; macro expansion tests use `SwiftSyntaxMacrosGenericTestSupport`.
- Gate scratch override is `GAMA_SCRATCH_ROOT`, not `SCRATCH_ROOT`. `check-mlir.sh` hardcodes `/private/tmp/gama-framework-swiftpm` with no override, so a filtered `swift test` and a concurrent MLIR gate collide.
- Drive `gama-demo` with the `run-gama` skill (tmux). It is mirrored at `.agents/skills/run-gama/` and `.claude/skills/run-gama/`; change both. `gama-demo` still owns `TUIRenderer` itself because of its plugin loop; `App.runAdaptive()` is the TTY-versus-pipe entry for ordinary apps.

## Verification

- Fast Apple gate: `./scripts/check-apple.sh` (debug build, all tests, release build).
- Portable ownership/import/symbol rules: `./scripts/check-boundaries.sh`.
- Documentation gates: `./scripts/check-docs.sh && ./scripts/check-doc-coverage.sh`. New public declarations need `///`; do not expand the coverage allowlist without a genuine baseline exception.
- Android cross-build/JNI packaging requires `ANDROID_NDK_HOME=... ./scripts/check-android.sh`.
- Full acceptance is `./scripts/check.sh`. Its `gates` array is authoritative and currently runs 15 fail-closed gates: Apple, Apple platforms, boundaries, concurrency negatives, C ABI, Embedded, Linux, WASM, Android, Android emulator, MLIR, DocC, doc coverage, evidence freshness, and package graph.
- python3 is a prerequisite of the documentation and boundary helpers; node is a prerequisite of the WASM gate.
- Some full-matrix gates require pinned SDKs, the NDK, Node/browser tooling, MLIR, or hosted non-macOS runners. Missing proof is a failure; do not weaken or skip gates to make the matrix green.
- CI truth is `.github/workflows/ci.yml`. Windows deliberately uses the pinned Swift 6.4.x exception; other jobs use the 6.5-dev snapshot family.

## Architecture Boundaries

- Flow: `App -> SceneBuilder -> RenderNode -> LayoutEngine -> CellPainter -> CellBuffer -> DrawList -> backend`; platform events return through `FrameHost`.
- Every app declares exactly one primary scene. All backends except `GamaAppleShell` render only that primary scene; the shell owns macOS auxiliary/multi-window surfaces.
- `GamaCore` and `GamaPlugin` are stdlib-only. The platform-import ban covers all five portable targets — `GamaCore`, `GamaPlugin`, `GamaDraw`, `GamaEmbed`, `GamaMLIR` — which may not import Foundation, platform UI/POSIX modules, WinSDK, or Synchronization, and framework state must not move into process-global registries. That target list is the same one `scripts/portable-global-state.py` uses; keep the two in step.
- `FrameHost` and `AppRuntime` are `~Copyable`; each host uniquely owns focus, actions, `@Reactive` state, subscriptions, dirty state, and frames. Out-of-band changes use host subscriptions or explicit `invalidate()`.
- `GamaPlatformServices` contains Foundation-backed host-service implementations. Only apps, demos, examples, and tests may import it; portable/framework targets must depend on service interfaces instead.
- `GamaMacrosImpl` is a host compiler plugin. `swift-syntax` is revision-pinned and build-time-only; shipped products must retain zero runtime package dependencies.
- Backends translate events and present shared `DrawList` output; do not fork layout, paint, or application semantics. Keep C `gama_embed_v1_*` and WASM `gama_web_v1_*`/`gama_web_v2_*` symbols versioned and separately namespaced; the WASM backend ships both tiers, `v2` being the argument-compatible status-reporting form (`docs/backends/WASM.md`).
- `CellPresenter` (mutating, swaps planes: TUI `AnsiPresenter` / `StreamPresenter`) and `CellSerializer` (non-mutating, no swap: WASM, Embed, and Apple `DrawListSerializer`) are distinct families. Do not unify them (`docs/superpowers/specs/2026-09-06-cell-serializer-design.md`).
- `App.runAdaptive()` selects interactive versus stream from stdout (`--gama-plain` / `--gama-tui`). An input-less stream run ends at the first quiescent frame; async work must declare `CompletionStatus` via `complete(_:)`. `FailureExitCode` is an opt-in `1...255` constructor used with `failure(exitCode:_:)`; it rejects `0`, negatives, and `256+` by failing construction. The unvalidated `failure(code:_:)` factory still accepts zero.

## State And Documentation Traps

- `@Reactive` is per-surface; a `Signal` on the `App` is shared (ADR 0011). Scene content closures run every frame, and a component constructed inline keeps its `@Reactive` state because `@Component`'s synthesized `render(in:)` binds each slot to the host's identity-keyed store; two windows of one `WindowGroup` get independent state, and a hoisted instance still writes per surface. Raw `Signal` properties inside components are unsupported; use `@Reactive` and `_name.binding()`.
- The binding cannot be skipped silently: `@Reactive` outside a struct marked `@Component` is error `reactive.requires-component`, and a hand-written `render(in:)` beside `@Reactive` properties is error `component.render-collision`. `FrameHost.transientStateIDs` reports storage replaced at an existing `(NodeID, slot)` key; it does not report new/removed keys or positional storage reuse. Positional `ForEach` state follows indices through reordering; use `IdentifiedForEach` or `.stateScope(_:)` when state must follow an element.
- Read `docs/README.md`, the relevant `docs/adr/` record, and `docs/backends/<Backend>.md` before changing a settled backend contract. Plugin tier/capability work starts with `docs/Plugins.md`.
- `docs/Capabilities.md` is the evidence ledger. Distinguish implemented, locally proven, hosted proven, provisional, and blocked behavior; implementation presence alone is not platform proof.
- `#expect` cannot read a bare property off a `~Copyable` host (`#expect(host.needsFrame)` does not compile). Bind first: `let dirty = host.needsFrame; #expect(dirty)`.
- `GEMINI.md` is a tracked empty placeholder; do not fill it. No gate reads it.

## Repository Safety

- Preserve `Package.resolved`. Never commit credentials or runner configuration, force-push `main`, or merge before required checks are green.
- Never run `git gc`, `git prune`, `git fsck`, or `git repack` in this FileProvider-managed checkout.
