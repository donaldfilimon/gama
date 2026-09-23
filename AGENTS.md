# Gama Agent Guide

## Repository Identity

- This is the SwiftPM Gama Framework checkout. `~/dev/active/gama-qt` is an unrelated Qt browser app.
- The module graph is `Package.swift`'s products and targets. Treat any other module list, or a `gama` CLI, as a design vision, not this checkout. Do not add targets to match it.
- The umbrella path is `Sources/gama` and the test path is `Tests/gamaTests`. A wrong-case `Sources/Gama` or `Tests/GamaTests` directory is not in the package. Linux CI is case-sensitive.
- The Android demo target path is `Examples/Android`, not a `Sources/GamaAndroidDemo` directory. JNI and Gradle stay there.

## Toolchain And Commands

- Run `unset TOOLCHAINS` before Swift commands. Everyday invocation is `swiftly run swift ...`; `.swift-version` pins `main-snapshot-2026-08-21` (Swift 6.5-dev). macOS check scripts select the compiler with `xcrun --toolchain "$GAMA_TOOLCHAIN_ID"`, not `swiftly`.
- `Package.swift` deliberately stays `swift-tools-version: 6.4` so Xcode's SwiftPM can resolve platform gates. `check-boundaries.sh` enforces this. `check-apple-platforms.sh` requires `xcrun --toolchain default` to report Swift 6.4. Do not raise the tools version to match the compiler pin.
- `Toolchains.toml` is the pin authority. `scripts/check-toolchain-pins.sh`, chained from the boundary gate, rejects drift in compiler/SDK revisions, URLs, and checksums; it discovers every `GAMA_TOOLCHAIN_ID` default rather than listing scripts, and fails on any checked-in home-directory path under `scripts/`.
- Scripts derive the pinned snapshot's location from `Toolchains.toml` through `scripts/lib/toolchain.sh`. Do not write an absolute toolchain path into a script; override with `GAMA_SWIFT_64` / `GAMA_SWIFTC_64` / `GAMA_EMBEDDED_TOOLCHAIN` instead.
- This checkout is iCloud/FileProvider-managed. `swift build` and `swift run` work in place. `swift test` does not (codesign detritus). Direct tests, `check-apple.sh`, and `check-mlir.sh` share `/private/tmp/gama-framework-swiftpm`. `GAMA_SCRATCH_ROOT` does not move those two (`GAMA_APPLE_SCRATCH_PATH`, and a hardcoded MLIR path). A bare `SCRATCH_ROOT` is ignored. DocC uses `GAMA_DOCC_SCRATCH_PATH`; the concurrency-negative gate uses `GAMA_CONCURRENCY_NEGATIVE_SCRATCH_PATH`.

```bash
unset TOOLCHAINS
swiftly run swift --version # must report 6.5-dev
swiftly run swift build
swiftly run swift test --scratch-path /private/tmp/gama-framework-swiftpm
swiftly run swift test --scratch-path /private/tmp/gama-framework-swiftpm --filter SceneGraphTests
swiftly run swift build --target GamaCore
swiftly run swift run gama-demo
.agents/skills/run-gama/driver.sh smoke   # tmux-driven TUI proof; do not pipe interactive gama-demo
```

- Test filters match Swift source identifiers, not `@Suite` display names. A non-matching filter prints a warning and exits 0; confirm the test count.
- Tests use Swift Testing (`import Testing`) only. Do not add XCTest; macro expansion tests use `SwiftSyntaxMacrosGenericTestSupport`. `Tests/CompileFail/` and `Tests/Fixtures/` are outside `GamaTests`. `swift test` does not run them. `check-concurrency-negative.sh` typechecks `Tests/CompileFail/` and fails if a fixture compiles. Do not "fix" a negative so it compiles.
- Interactive `gama-demo` has no pipe fallback; drive it with the `run-gama` skill (tmux). `--emit-mlir` prints and exits before the renderer and may be redirected. The skill is mirrored at `.agents/skills/run-gama/` and `.claude/skills/run-gama/`. A plain diff of the two `SKILL.md` files always differs; `check-docs.sh` is the parity authority. Change both. `gama-demo` still owns `TUIRenderer` itself because of its plugin loop; `App.runAdaptive()` is the TTY-versus-pipe entry for ordinary apps.

## Verification

- Fast Apple gate: `./scripts/check-apple.sh` (debug build, all tests, release build).
- Portable ownership/import/symbol rules: `./scripts/check-boundaries.sh`.
- Source policies alone: `./scripts/check-boundaries.sh --source-policies-only` stops before `scripts/test-boundary-paths.py` and any `xcrun`, so it needs no toolchain. Unflagged, the gate runs that unittest, whose target tuple is a deliberate fourth copy of the scan scope: rename or remove anything under `Sources/` and it fails until the shell arrays, `portable-global-state.py`, and the tuple all agree.
- Documentation gates: `./scripts/check-docs.sh && ./scripts/check-doc-coverage.sh`. New public declarations need `///`; do not expand the coverage allowlist without a genuine baseline exception. `scripts/referenced-paths.py` and `scripts/evidence-locality.py` scan this file. Do not backtick a missing root-anchored path. Evidence claims belong only in `docs/Capabilities.md`.
- Android cross-build/JNI packaging requires `ANDROID_NDK_HOME=... ./scripts/check-android.sh`.
- Full acceptance is `./scripts/check.sh`. Its `gates` array is authoritative and currently runs 15 fail-closed gates: Apple, Apple platforms, boundaries, concurrency negatives, C ABI, Embedded, Linux, WASM, Android, Android emulator, MLIR, DocC, doc coverage, evidence freshness, and package graph. `scripts/check-linux-leaks.sh` is not in that array; off Linux it exits 2. Do not add it to make leak proof local.
- python3 is a prerequisite of the documentation and boundary helpers; node is a prerequisite of the WASM gate.
- Some full-matrix gates require pinned SDKs, the NDK, Node/browser tooling, MLIR, or hosted non-macOS runners. Missing proof is a failure; do not weaken or skip gates to make the matrix green. `check-evidence-freshness.sh` resolves anchors against git history; a depth-1 clone fails closed.
- CI truth is `.github/workflows/ci.yml`. Windows deliberately uses the pinned Swift 6.4.x exception; other jobs use the 6.5-dev snapshot family. Push to `main` also deploys the WASM site via `.github/workflows/pages.yml`.

## Architecture Boundaries

- Flow: `App -> SceneBuilder -> RenderNode -> LayoutEngine -> CellPainter -> CellBuffer -> DrawList -> backend`; platform events return through `FrameHost`.
- Every app declares exactly one primary scene. All backends except `GamaAppleShell` render only that primary scene; the shell owns macOS auxiliary/multi-window surfaces.
- The platform-import ban covers five portable targets: `GamaCore`, `GamaPlugin`, `GamaDraw`, `GamaEmbed`, `GamaMLIR`. They may not import Foundation, platform UI/POSIX modules, WinSDK, or Synchronization. That ban and the `nonisolated(unsafe)` / global-actor hatch share one `TARGETS` list in `scripts/portable-global-state.py`, which fails closed on a missing or empty target. Do not add backends to that list. Named registry literals, the `GamaPlatformServices` inverse ban, and the libm scan are separate pins. Do not collapse them.
- Signal installation stays in `Sources/GamaTUISignal/GamaTUISignal.c`. `Sources/GamaTUI/TerminalRescue.swift` must not contain `sigaction`, `atexit`, `@convention(c)`, or `nonisolated(unsafe)`.
- `scripts/check-embedded.sh` compiles `Sources/GamaCore` alone. `Sources/GamaCore/HostPump.swift` must stay there; moving the pump policy to `GamaDraw` fails the gate.
- Tier-1 plugins are cooperative in-process code, not a sandbox. Tiers 2 and 3 are Proposed. Read `docs/Plugins.md` before changing tier, capability, or lifecycle contracts.
- `FrameHost` and `AppRuntime` are `~Copyable`; each host uniquely owns focus, actions, `@Reactive` state, subscriptions, dirty state, and frames. Out-of-band changes use host subscriptions or explicit `invalidate()`.
- `GamaPlatformServices` contains Foundation-backed host-service implementations. Only apps, demos, examples, and tests may import it; portable/framework targets must depend on service interfaces instead.
- `GamaMacrosImpl` is a host compiler plugin. `swift-syntax` is revision-pinned and build-time-only; shipped products must retain zero runtime package dependencies.
- Layout flexibility is per-axis: use `flexPriority(along:)`. The axis-agnostic `RenderNode.flexPriority` property is deprecated and layout does not consult it (ADR 0013).
- Shipped libraries and macros use `strictLibrary` (strict memory safety as an error). Executables and `GamaTests` stay on `strictCore` (Swift 6, `ExistentialAny`, `MemberImportVisibility`, `InternalImportsByDefault`). A member visible in one file is rejected in another until that file imports the defining module. Public API needs `public import`; an unused `public import` is an error. `Extern` is legal only on `GamaWASM`. `NonisolatedNonsendingByDefault` is banned. Do not add Swift sources to C-only `GamaEmbedABI` or `GamaTUISignal` without the settings `scripts/package-graph.py` requires.
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
