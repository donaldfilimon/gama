# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Read `AGENTS.md` first; it is the canonical project guide. This file adds the
operational detail (commands, architecture map, environment traps) that agents
need to be productive.

This is the canonical checkout of `donaldfilimon/gama` — the Gama Framework
umbrella (retained UI core, plugins, macros, drawing,
TUI/Apple/WASM/Embed/MLIR backends, and platform capability services). The Qt
adapter was removed on 2026-08-26; `~/dev/active/gama-qt` is an unrelated Qt
browser app that shares only the name.

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
./scripts/check-doc-coverage.sh # every public decl needs a doc comment
```

`check-doc-coverage.sh` fails on any undocumented public declaration;
baseline exceptions live in `scripts/doc-coverage-allowlist.txt` with a
written justification. Adding a public symbol means adding its `///`, not an
allowlist entry. CI's macOS job runs boundaries, docs, and doc-coverage
together.

Full acceptance matrix: `./scripts/check.sh` runs every `check-*.sh` gate in
order — twelve as of 2026-08-27 (apple, apple-platforms, boundaries, c-abi,
embedded, linux, wasm, android, android-emulator, mlir, docs, doc-coverage);
the `gates=(…)` array in `scripts/check.sh` is the authority. Parts require pinned SDKs,
the NDK, node, or CI/Linux — it intentionally fails when a prerequisite or
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
`ANDROID_NDK_HOME=… ./scripts/check-android.sh`. Other executables:
`gama-apple-demo` (macOS scene/window lifecycle), `gama-web-demo` (browser
reactor served from `WebHost/`), `gama-windows-console-smoke` (Windows
acceptance binary).

Tests are Swift Testing only. The single test target is `GamaTests` at
`Tests/gamaTests`. `--filter` matches the source identifier, not the `@Suite`
display name: use the struct name (`--filter SceneGraphTests`), not
`--filter 'Scene graph'`. Plugin and capability-service coverage lives in
`PluginRuntimeTests`, `PluginSlotTests`, `PluginSceneTests`,
`PluginCommandTests`, and `PlatformServicesTests`.
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
App → @SceneBuilder → one explicit primary + auxiliary Window/WindowGroup
          → per-surface content closure, re-evaluated every frame
App state → @ViewBuilder / macros → RenderNode (value IR, GamaCore)
          → LayoutEngine → LaidOutNode
          → CellPainter → CellBuffer → DrawList (GamaDraw)
          → GamaTUI | GamaAppleUI/GamaAppleShell | GamaWASM
          | GamaEmbed (C ABI) | GamaMLIR

platform event → InputEvent → FrameHost → host-owned action → rebuild
```

The surface is scene-first: an `App` declares `scenes`, exactly one scene is
`role: .primary`, and every backend except the macOS shell renders only that
primary scene. `App.content` is gone — `docs/SceneMigration.md` records the
deliberate pre-release break. `AppRuntime` and `FrameHost` are `~Copyable`
with typed throws, so hosts are moved, never shared.

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
- **GamaPlugin** — stdlib-only Tier-1 static plugin and capability model:
  manifests, deny-by-default grants, unforgeable host-service handles
  (internal initializers), per-host `PluginRuntime`/`PluginSlot`, and opt-in
  slot/scene/command contributions. It depends on GamaCore and defines
  service interfaces only. Tier 1 is capability-based *design*, not a
  sandbox: in-process plugins are cooperative code — never describe it as
  isolation. Tiers 2/3 are Proposed. Read `docs/Plugins.md` before changing
  its tier, capability, lifecycle, or contribution contracts.
- **GamaPlatformServices** — Foundation-backed implementations for the
  `HostServices` interfaces (standard logging, monotonic time, contained
  filesystem access). It is the platform-capability layer, not a portable
  framework dependency: only applications, demos, examples, and tests may
  import it. `check-boundaries.sh` rejects imports from every
  portable/framework target, routing OS-backed services outward through this
  target instead.
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
  (NSApplication/NSWindow ownership, multi-window and per-shell command
  routing; compiles to an inert target without AppKit — it is the one
  backend that renders auxiliary scenes), GamaWASM
  (browser reactor, `gama_web_v1_*` exports, inert stubs off wasm32,
  experimental `Extern` feature scoped to this target only; `WebHost/` holds
  the page and JS glue the web demo is served from), GamaEmbed +
  GamaEmbedABI (context-owned flat C ABI `gama_embed_v1_*`; C header and
  ownership rules in `Sources/GamaEmbedABI/include/GamaEmbed.h`; static so the
  entry points fold into the host binary), GamaMLIR (deterministic textual
  `gama` dialect emitter — not a Swift MLIR frontend).
- C and WASM symbols remain versioned and separately namespaced.
- `Examples/` holds host integrations kept out of the framework targets:
  `Android` (JNI/Gradle, built as the `GamaAndroidDemo` product), plus
  `AppleHost`, `CEmbed`, and `Embedded` consumer samples.

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
`docs/superpowers/specs/` (`drafts/` are open questions, not commitments);
the running goal ledger is `tasks/goals.md` + `tasks/todo.md`.

Before changing a backend or a settled design, read its record rather than
re-deriving it: `docs/README.md` is the index, `docs/adr/` holds the seven
decision records (own-the-rendering, toolchain pinning, Swift-Testing-only,
signal confinement, DrawList wire format, noncopyable hosts, frame pumps),
`docs/Plugins.md` defines the plugin tiers and capability model,
`docs/backends/<Backend>.md` the per-backend guides, and
`Sources/GamaCore/GamaCore.docc/` the symbol-level articles built by
`check-docs.sh`.
