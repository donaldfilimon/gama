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
./scripts/check-boundaries.sh   # portable imports/ownership + emitted-symbol scan
./scripts/check-docs.sh         # symbol graph + docc, zero-warning
./scripts/check-doc-coverage.sh # every public decl needs a doc comment
```

`check-doc-coverage.sh` fails on any undocumented public declaration;
baseline exceptions live in `scripts/doc-coverage-allowlist.txt` with a
written justification. Adding a public symbol means adding its `///`, not an
allowlist entry. CI's macOS job runs boundaries, docs, and doc-coverage
together.

Full acceptance matrix: `./scripts/check.sh` runs every gate in order. **The
`gates=(…)` array at the top of `scripts/check.sh` is the authority — read it
rather than any list written down elsewhere, including this file.** It is
thirteen entries at time of writing. Parts require pinned SDKs, the NDK, node,
or CI/Linux, and the matrix intentionally fails when a prerequisite or a
required runtime proof is unavailable. Do not weaken or skip a gate to make it
green.

Two gates compile fixtures that live outside the test target and are
therefore invisible to `swift test`: `check-concurrency-negative.sh`
`-typecheck`s `Tests/CompileFail/`, failing unless each file is still
*rejected* with the unavailable-`Sendable` diagnostic (the enforcement behind
ADR 0009 keeping `Signal` and `PluginRuntime` non-`Sendable`), and
`check-boundaries.sh` drives `Tests/Fixtures/`: `Ownership/` (`error.*` must
fail, `ok.*` must compile) pins the `~Copyable` `Terminal` contract of ADR
0010, `Confinement/` pins ADR 0009 at the fixture level (`error.*` must fail
to compile; `warn.*` must compile and emit `#UnavailableSendableConformance`),
`PortableSymbols/` is a fixture package proving the libm-symbol scan catches
a real offender, and `TerminalSignal/` is a C probe that runs the signal
handler outside Swift (re-raise through the displaced disposition, no write
to a blocking tty on a fatal signal). Changing those contracts means updating
the fixtures, not `GamaTests`.

Gates also chain Python helpers that fail on their own: `check-docs.sh` runs
`scripts/check-doc-links.py` (relative Markdown links) before DocC, and
`check-wasm.sh` runs `scripts/check-wasm-unsafe-declarations.py` before the
SDK build. The pre-push documentation checklist is the block in
`CONTRIBUTING.md`: `./scripts/check-docs.sh` (which already runs the link
checker's self-test plus the repo scan) followed by
`./scripts/check-doc-coverage.sh`.

`check-linux-leaks.sh` and `check-portable-symbols.sh` are not in that array:
the first is a hosted-Linux LeakSanitizer proof (it exits non-zero on macOS by
design — macOS can build `gama-leak-check` but cannot produce the evidence),
and the second is a helper the platform gates call to scan emitted objects for
forbidden libm/libc symbols.

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
acceptance binary), and `gama-bench` (deterministic frame-path measurement;
measure release builds only, it reports numbers, asserts no threshold, and is
not a gate — rules and baselines in `docs/Performance.md`).

Tests are Swift Testing only. The single test target is `GamaTests` at
`Tests/gamaTests`. `--filter` matches the source identifier, not the `@Suite`
display name: use the struct name (`--filter SceneGraphTests`), not
`--filter 'Scene graph'`. A non-matching filter prints "No matching test
cases were run" and **exits zero**, so confirm the final test count rather
than the exit status. Plugin and capability-service coverage lives in
`PluginRuntimeTests`, `PluginSlotTests`, `PluginSceneTests`,
`PluginCommandTests`, and `PlatformServicesTests`.
Do not add `import XCTest`. Macro expansion tests use
`SwiftSyntaxMacrosGenericTestSupport`. See `docs/Testing.md` and
`docs/Toolchain.md`.

CI is `.github/workflows/ci.yml` — six jobs pinned to the same snapshot family
with SHA256-verified downloads (`scripts/ci-install-swift-*.sh`).
`scripts/check-toolchain-pins.sh` (via `check-boundaries.sh`) fails if CI
URLs/SHAs drift from `Toolchains.toml`. A second workflow,
`.github/workflows/pages.yml`, runs `scripts/bundle-web.sh` on every push to
`main` and deploys the browser-smoked WASM site to GitHub Pages, so a merge
to `main` is also a web deploy. `main` is protected by a repository ruleset:
pull requests only, no force-push or deletion, and all six CI jobs are
required status checks under the strict policy, so a PR must be current with
`main` before it can merge. That is GitHub-side state, not repo state, so
re-check it with `gh api repos/donaldfilimon/gama/rulesets` rather than
trusting this line.

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
- **Gama** — compatibility umbrella (`@_exported import GamaCore`) only. Its
  source path is the lowercase `Sources/gama` (set explicitly in
  `Package.swift`); the case-insensitive local filesystem hides a wrong-case
  reference that Linux CI will not.
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
- Every Swift target builds in Swift 6 language mode with the `ExistentialAny`
  and `MemberImportVisibility` upcoming features (`strictCore` in
  `Package.swift`; the C-only `GamaTUISignal` and `GamaEmbedABI` carry no
  Swift settings), so a member that compiles in one file is rejected in
  another until that file imports the defining module itself. `GamaAppleUI`
  adds `InferIsolatedConformances`; `GamaWASM` adds experimental `Extern`.
- **GamaMacros / GamaMacrosImpl** — optional `@Component`, `@Reactive`, `#rgb`
  sugar; the impl is a host-side compiler plugin. swift-syntax is the only
  package dependency, pinned by revision, build-time only — nothing from it
  links into shipped products (zero-runtime-dependency constraint).
- **GamaDraw** — platform-free rasterizer shared by every backend: CellBuffer
  (double-buffered grid + ANSI diff), CellPainter (IR → cells), DrawList
  (cells → vector commands + versioned little-endian binary, magic `GAMA`,
  version 1).
- **Backends** translate events in and present `DrawList` out; they never fork
  application semantics. GamaTUI (POSIX termios + Windows Console VT; its
  signal handling lives in the **C-only** `GamaTUISignal` target so that
  dispositions, restore bytes, and `sig_atomic_t` latches never run Swift
  runtime code in async-signal context — do not reimplement it in Swift),
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
- `gama-leak-check` is a plain executable, not a test: `check-linux-leaks.sh`
  builds it with `--sanitize address` and runs the binary directly, because
  neither Swift Testing nor XCTest may sit above the allocation stacks the
  gate audits. Adding lifecycle coverage there means editing
  `Sources/GamaLeakCheck/main.swift`, not `GamaTests`.

## Packaging

`scripts/bundle-macos.sh`, `scripts/bundle-web.sh`, and
`scripts/release-macos.sh` read identity and branding from the flat manifests
in `Distribution/` (`gama-apple-demo.toml`, `gama-web-demo.toml`) through
`scripts/lib/manifest.sh`. That reader accepts only blank lines, `#` comments,
`[section]` headers, and `key = "value"` — anything else fails the whole read.
That strictness is the guard keeping manifests identity/branding-only rather
than a second build system, so extend the manifest schema, never the grammar.
Rationale is in `docs/Packaging.md`.

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
framework-provided storage today. The fix is an accepted, unimplemented
design: `docs/superpowers/specs/2026-08-29-view-state-identity-design.md`,
tracked as open work in `tasks/todo.md` — acceptance is not an implementation
claim.
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
`docs/superpowers/specs/` (`drafts/` are open questions, not commitments) and
dated execution plans in `docs/superpowers/plans/`; neither is a capability
claim. The running goal ledger is `tasks/goals.md` + `tasks/todo.md`.

Before changing a backend or a settled design, read its record rather than
re-deriving it: `docs/README.md` is the index, `docs/adr/0000-index.md`
lists every decision record with its status (some are superseded, so read
the table rather than assuming each file is live), `docs/Plugins.md` defines the plugin tiers and capability model,
`docs/backends/<Backend>.md` the per-backend guides, and
`Sources/GamaCore/GamaCore.docc/` the symbol-level articles built by
`check-docs.sh`.
