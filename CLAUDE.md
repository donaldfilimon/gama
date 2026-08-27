# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Read `AGENTS.md` first; it is the canonical project guide. This file adds the
operational detail (commands, architecture map, environment traps) that agents
need to be productive.

This is the canonical checkout of `donaldfilimon/gama` — the Gama Framework
umbrella (retained UI core, macros, drawing, TUI/Apple/WASM/Embed/MLIR
backends). The Qt adapter was removed on 2026-08-26; `~/dev/active/gama-qt`
is an unrelated Qt browser app that shares only the name.

## Toolchain — this repo overrides the machine-wide Swift rule

`.swift-version` pins `main-snapshot-2026-08-21` (Apple Swift 6.5-dev,
toolchain id `org.swift.65202608211a`). The manifest deliberately stays
`swift-tools-version: 6.4` so Xcode's integrated SwiftPM can still resolve the
package (the xcodebuild platform gates depend on that) — the 6.5-dev identity
lives in the compiler pin, not the manifest grammar. `check-boundaries.sh`
enforces the 6.4 tools-version line, so do not "upgrade" it.

Always `unset TOOLCHAINS` first — a stray value overrides both the swiftly
shim and the scripts' explicit `xcrun --toolchain` pins.

**Preferred everyday invocation: `swiftly run`.** From the repo root,
`swiftly run swift <build|run|test|…>` reads `.swift-version` and selects the
pinned snapshot automatically — the same compiler the scripts pin via `xcrun
--toolchain org.swift.65202608211a`, without hardcoding the id. Sanity-check
with `swiftly run swift --version` → must report `6.5-dev`.

The check scripts are the authority on toolchain identity: they verify
`Swift version 6.5` (and for the Embedded gate, the exact compiler SHA256 and
revision) and fail loudly on mismatch. `Toolchains.toml` records pinned
artifact URLs/SHA256s for non-Apple platforms; Windows deliberately remains on
the 6.4.x snapshot. Override knobs: `GAMA_TOOLCHAIN_ID`, `GAMA_SWIFT_64` /
`GAMA_SWIFTC_64` (+ `GAMA_SWIFTC_SHA256`), and per-gate scratch paths like
`GAMA_APPLE_SCRATCH_PATH`.

## iCloud constraints (measured, not theoretical)

This tree is FileProvider-managed. In-place `swift test` fails at codesign
("resource fork, Finder information, or similar detritus not allowed");
`xattr -rc` does not fix it. The check scripts already route builds through
`/private/tmp` scratch paths — use them, or pass `--scratch-path` outside
iCloud yourself. `swift build` / `swift run` work in place.

Git: prefer `.git`-internal reads; `git status` can hang here. NEVER run
`git gc`, `git prune`, `git fsck`, or `git repack` in this directory.

## Commands

Everyday local gates (fast, macOS-only prerequisites):

```bash
unset TOOLCHAINS
./scripts/check-apple.sh        # debug build + tests + release build
./scripts/check-boundaries.sh   # portable-core import/ownership greps
./scripts/check-docs.sh         # symbol graph + docc, zero-warning
```

Full acceptance matrix: `./scripts/check.sh` runs every `check-*.sh` gate in
order (apple, apple-platforms, boundaries, c-abi, embedded, linux, wasm,
android, android-emulator, mlir, docs). Parts require pinned SDKs, the NDK,
node, or CI/Linux — it intentionally fails when an exact prerequisite or
required runtime proof is unavailable. Do not weaken or skip a gate to make
the matrix green.

Run tests directly (single test, filtered) — must use a scratch path outside
iCloud:

```bash
unset TOOLCHAINS
swiftly run swift test \
  --scratch-path /private/tmp/gama-framework-swiftpm --filter <TestNamePattern>
```

(`/usr/bin/xcrun --toolchain org.swift.65202608211a swift test …` is the
equivalent explicit form the scripts use.)

Run the terminal demo:

```bash
unset TOOLCHAINS
swiftly run swift run gama-demo
```

`gama-demo --emit-mlir` prints the MLIR dialect form. Android needs
`ANDROID_NDK_HOME=… ./scripts/check-android.sh`.

Tests are Swift Testing only. Filter with `--filter SuiteName.testName`.
Do not add `import XCTest`. Macro expansion tests use
`SwiftSyntaxMacrosGenericTestSupport`. See `docs/Testing.md` and
`docs/Toolchain.md`.

CI is `.github/workflows/ci.yml` — six jobs pinned to the same snapshot family
with SHA256-verified downloads (`scripts/ci-install-swift-*.sh`).
`scripts/check-toolchain-pins.sh` (via `check-boundaries.sh`) fails if CI
URLs/SHAs drift from `Toolchains.toml`.

## Architecture

One retained render pipeline, many backends:

```text
App state → @ViewBuilder / macros → RenderNode (value IR, GamaCore)
          → LayoutEngine → LaidOutNode
          → CellPainter → CellBuffer → DrawList (GamaDraw)
          → GamaTUI | GamaAppleUI | GamaWASM | GamaEmbed (C ABI) | GamaMLIR

platform event → InputEvent → FrameHost → host-owned action → rebuild
```

Target layering (all under `Sources/`, single test target `Tests/gamaTests`):

- **GamaCore** — views, identity, state, layout, events, and `FrameHost`.
  Embedded-Swift-safe: stdlib only. `check-boundaries.sh` rejects any import
  of Foundation, AppKit, UIKit, Darwin, Glibc, WinSDK, or Synchronization
  here, and rejects process-global registries anywhere. Each `FrameHost` owns
  focus, actions, subscriptions, dirty state, and frames; out-of-band changes
  go through the host's `SubscriptionContext` or explicit `invalidate()`.
- **GamaMacros / GamaMacrosImpl** — optional `@Component`, `@Reactive`, `#rgb`
  sugar; the impl is a host-side compiler plugin. swift-syntax is the only
  package dependency, pinned by revision, build-time only — nothing from it
  links into shipped products (zero-runtime-dependency constraint).
- **GamaDraw** — platform-free rasterizer shared by every backend: CellBuffer
  (double-buffered grid + ANSI diff), CellPainter (IR → cells), DrawList
  (cells → vector commands + versioned little-endian binary, magic `GAMA`,
  version 1).
- **Backends** translate events in and present `DrawList` out; they never fork
  application semantics. GamaTUI (POSIX termios + Windows Console VT),
  GamaAppleUI (`@MainActor` NSView/UIView via CoreGraphics), GamaWASM
  (browser reactor, `gama_web_v1_*` exports, inert stubs off wasm32,
  experimental `Extern` feature scoped to this target only), GamaEmbed +
  GamaEmbedABI (context-owned flat C ABI `gama_embed_v1_*`; C header and
  ownership rules in `Sources/GamaEmbedABI/include/GamaEmbed.h`; static so the
  entry points fold into the host binary), GamaMLIR (deterministic textual
  `gama` dialect emitter — not a Swift MLIR frontend).
- C and WASM symbols remain versioned and separately namespaced.
- `Examples/Android` holds the JNI/Gradle sample (`GamaAndroidDemo`); it never
  enters the portable framework targets.

## Evidence policy

Implementation presence is not platform proof. `docs/Capabilities.md` is the
evidence ledger: a backend is Current only when its declared compile/runtime
gate passes, and documentation must distinguish implemented, locally proven,
hosted proven, provisional, and blocked states. Never describe a blocked
capability (e.g. Windows console native proof) as shipped.

## Conventions

Prefer small reviewable commits, preserve `Package.resolved`, never commit
credentials or runner configuration, never force-push the default branch, and
only merge after required checks are green. Design specs live in
`docs/superpowers/specs/`; the running goal ledger is `tasks/goals.md`.
