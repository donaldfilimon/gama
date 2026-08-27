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
./scripts/check-doc-coverage.sh # per-symbol public-API doc coverage
```

`check-doc-coverage.sh` drives `scripts/doc-coverage.py` against the symbol
graph; the only sanctioned escape is an entry in
`scripts/doc-coverage-allowlist.txt`. CI's macOS job runs boundaries, docs,
and doc-coverage together.

Full acceptance matrix: `./scripts/check.sh` runs every `check-*.sh` gate in
order (apple, apple-platforms, boundaries, c-abi, embedded, linux, wasm,
android, android-emulator, mlir, docs, doc-coverage). Parts require pinned
SDKs, the NDK, node, or CI/Linux — it intentionally fails when an exact
prerequisite or required runtime proof is unavailable. Do not weaken or skip
a gate to make the matrix green.

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
App.scenes → Window / WindowGroup (exactly one role: .primary)
          → per-surface content closure (re-evaluated every frame)
          → @ViewBuilder / macros → RenderNode (value IR, GamaCore)
          → LayoutEngine → LaidOutNode
          → CellPainter → CellBuffer → DrawList (GamaDraw)
          → GamaTUI | GamaAppleUI + GamaAppleShell | GamaWASM
            | GamaEmbed (C ABI) | GamaMLIR

platform event → InputEvent → FrameHost → host-owned action → rebuild
```

Applications are scene-first: `App` declares `scenes`, not `content`, and
exactly one scene must be `role: .primary`. Single-surface backends (TUI,
WASM, Embed, Android, MLIR) render only that primary scene; only
GamaAppleShell opens auxiliary windows and typed `WindowGroup` payloads. The
pre-release `App.content` break is documented in `docs/SceneMigration.md`.

Target layering (all under `Sources/`, single test target `GamaTests` at
`Tests/gamaTests`):

- **GamaCore** — scenes, views, identity, state, layout, events, and
  `FrameHost`. Embedded-Swift-safe: stdlib only. `check-boundaries.sh`
  rejects any import of Foundation, AppKit, UIKit, Darwin, Glibc, WinSDK, or
  Synchronization in GamaCore *and* GamaPlugin, and rejects process-global
  registries anywhere. `FrameHost` and `AppRuntime` are `~Copyable`: each
  host uniquely owns focus, actions, subscriptions, dirty state, and frames;
  out-of-band changes go through the host's `SubscriptionContext` or explicit
  `invalidate()`.
- **Gama** — compatibility umbrella (`@_exported import GamaCore`) only.
- **GamaPlugin** — Tier-1 static plugin runtime: manifest, grants,
  unforgeable handles (internal initializers), per-host `PluginRuntime` and
  `PluginSlot`. Stdlib-only, interfaces only. Tier 1 is capability-based
  *design*, not a sandbox — never describe it as isolation. Tiers 2/3 are
  Proposed. `docs/Plugins.md` carries the tier table and the honest
  enforcement statement.
- **GamaPlatformServices** — the Foundation-backed `HostServices`
  implementations (stderr log, monotonic clock, scoped filesystem). It may
  import Foundation precisely because no portable target may import *it*;
  `check-boundaries.sh` enforces that inverse boundary.
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
  GamaAppleUI (`@MainActor` NSView/UIView via CoreGraphics), GamaAppleShell
  (NSApplication/NSWindow ownership, lifecycle, per-shell window command
  routing; compiles inert without AppKit), GamaWASM
  (browser reactor, `gama_web_v1_*` exports, inert stubs off wasm32,
  experimental `Extern` feature scoped to this target only), GamaEmbed +
  GamaEmbedABI (context-owned flat C ABI `gama_embed_v1_*`; C header and
  ownership rules in `Sources/GamaEmbedABI/include/GamaEmbed.h`; static so the
  entry points fold into the host binary), GamaMLIR (deterministic textual
  `gama` dialect emitter — not a Swift MLIR frontend).
- C and WASM symbols remain versioned and separately namespaced.
- `Examples/Android` holds the JNI/Gradle sample (`GamaAndroidDemo`); it never
  enters the portable framework targets.

## State lifetime trap (`@Reactive`)

A scene's content closure runs **on every frame**, so a component value built
inside it is a fresh instance each frame — and `@Reactive` stores its
`Signal` in the component instance. Build a component inline in a `Window`
body and its state resets before the next pump: keypresses appear to do
nothing while the focus ring still moves. Hoist the instance so it outlives
the closure (`Sources/GamaDemo/main.swift:132` does this).

Hoisting stores state **per scene declaration, not per surface**: every
window of a `WindowGroup` captures the same closure, so a hoisted instance or
an app-level `Signal` is one shared instance behind all of them (`Signal`
also requires one host at a time, never concurrent hosts). That is right for
deliberately shared model state and wrong for per-window state, which has no
framework-provided storage today — the gap is tracked in
`docs/superpowers/specs/drafts/2026-08-27-view-state-identity-draft.md`.
`ReactiveStateLifetimeTests` (in `Tests/gamaTests/MacroUsageTests.swift`)
pins the behavior.

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
`docs/superpowers/specs/` (drafts under `drafts/`); the running goal ledger is
`tasks/goals.md`. Standing decisions are ADRs in `docs/adr/` (0001 own the
rendering, 0002 toolchain pinning, 0003 Swift-Testing-only, 0004 signal
confinement, 0005 DrawList wire format, 0006 noncopyable hosts, 0007 frame
pumps) — read the relevant one before relitigating its axis. Per-backend
notes live in `docs/backends/`.
