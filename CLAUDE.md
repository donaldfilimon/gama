# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Read `AGENTS.md` first; it is the canonical project guide. This file adds the
operational detail (commands, architecture map, environment traps) that agents
need to be productive. `GEMINI.md` is tracked but **empty** (0 bytes, added by
`1b07bcb` on 2026-09-04); it is a placeholder, not a third guide, and no gate
reads it — do not treat its emptiness as missing documentation to fill.

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

Always `unset TOOLCHAINS` first. **Measured 2026-09-06, narrower than this
file previously claimed:** a stray value overrides a *bare* `xcrun swift`
(6.4 becomes the snapshot, or the reverse), but it did **not** override an
explicit `xcrun --toolchain <id>`, and it did not override the `swiftly` shim.
Every check script passes the flag explicitly, so none of them is vulnerable
today; `unset TOOLCHAINS` remains correct for hand-typed commands and is cheap
insurance if a script ever drops the flag. Do not cite the old, broader claim
as a reason to change a script.

**Preferred everyday invocation: `swiftly run`.** From the repo root,
`swiftly run swift <build|run|test|…>` reads `.swift-version` and selects the
pinned snapshot automatically — the same compiler the scripts pin via `xcrun
--toolchain org.swift.65202608211a`, without hardcoding the id. Sanity-check
with `swiftly run swift --version` → must report `6.5-dev`.

The check scripts are the authority on toolchain identity, and they do not all
want the same compiler. Every gate that asserts a version string asserts
`Swift version 6.5` (and the Embedded gate additionally pins the exact compiler
SHA256 and revision) **except `check-apple-platforms.sh`, which runs
`xcrun --toolchain default` and fails unless it reports `Swift version 6.4`** —
it drives `xcodebuild` for the iOS/tvOS/visionOS `GamaAppleUI` compiles, which
go through Xcode's integrated SwiftPM. That gate is the concrete reason the
manifest stays `swift-tools-version: 6.4`: raising the tools version to match
the compiler pin would take the platform gates with it. `Toolchains.toml`
records pinned artifact URLs/SHA256s for non-Apple platforms; Windows
deliberately remains on the 6.4.x snapshot. Override knobs: `GAMA_TOOLCHAIN_ID`,
`GAMA_SWIFT_64` / `GAMA_SWIFTC_64` (+ `GAMA_SWIFTC_SHA256`).

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
fifteen entries as of 2026-09-06, having been thirteen earlier the same day —
the count moves, the array does not lie. Parts require pinned SDKs, the NDK, node,
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

Gates also chain helpers that fail on their own, so a gate's name understates
what it covers. `check-docs.sh` runs `scripts/check-doc-links.py` (relative
Markdown links), `scripts/evidence-locality.py` (no anchored evidence claim or
CI run id outside `docs/Capabilities.md` — measurement conditions such as the
commits `docs/Performance.md` benchmarks ran at are deliberately not claims),
`scripts/referenced-paths.py` (no document may name a root-anchored repository
path the tree lacks; bare filenames and module-relative fragments are prose,
not claims, and `docs/superpowers/plans/` and `specs/drafts/` are excluded
because a proposal may name what it proposes), **and
`scripts/check-run-gama-skill.sh`** before DocC;
`check-wasm.sh` runs `scripts/check-wasm-unsafe-declarations.py` and then two
Node smoke drivers (`wasm-runtime-smoke.mjs`, `browser-runtime-smoke.mjs`,
each self-tested first and then run against the built artifact), so **node is a
prerequisite of the WASM gate**, not just Python. `check-boundaries.sh` chains
`check-portable-symbols.sh`, `check-toolchain-pins.sh`, and
`scripts/portable-global-state.py` (which rejects `nonisolated(unsafe)` and
global-actor isolation in `GamaCore`, `GamaPlugin`, `GamaDraw`, `GamaEmbed`,
and `GamaMLIR` — Swift 6 language mode already rejects a bare stored `static
var`, so those two hatches are all that is left to police; backends are out of
scope, `GamaWASM/WASMHost.swift:89` being a justified single-threaded use), and
`check-doc-coverage.sh` chains `scripts/doc-coverage.py`, so **python3 is a
prerequisite of the documentation gates**, not only the WASM one. The pre-push
documentation checklist is the block in `CONTRIBUTING.md`:
`./scripts/check-docs.sh` followed by `./scripts/check-doc-coverage.sh`.

`check-linux-leaks.sh` and `check-portable-symbols.sh` are not in that array:
the first is a hosted-Linux LeakSanitizer proof (it exits non-zero on macOS by
design — macOS can build `gama-leak-check` but cannot produce the evidence),
and the second is a helper the platform gates call to scan emitted objects for
forbidden libm/libc symbols.

**Gates 14 and 15 landed on 2026-09-06 and both mechanize a policy that was
previously prose.** `check-evidence-freshness.sh` (gate 14, `67377af`) runs
`scripts/evidence-freshness.py`, which fails a `docs/Capabilities.md` row whose
evidence anchor predates the last change to the paths that row's claim depends
on. Each row carries one annotation in its third cell:
`<!-- evidence: layer=<token> anchor=<40-hex-sha> paths=<comma,separated> -->`.
It is fail-closed three ways — an unannotated row fails, zero parsed rows fails
(a table reformat must break loudly rather than quietly check nothing), and a
vocabulary term with no rule fails — and its lead-word rule additionally
requires the row's second cell to *start* with its declared layer word. Never
invent a different annotation grammar; the regexes in that script are the
authority. **Its reach is one file:** `LEDGER = "docs/Capabilities.md"`, so
hosted-evidence prose anywhere else (`docs/Packaging.md` carries a table of the
same shape) is still unchecked and can go stale silently.
`check-package-graph.sh` (gate 15, `f267270`) dumps the manifest and asserts
ADR 0012's `strictLibrary` scope, the zero-runtime-package-dependency
guarantee, and experimental-feature scoping — three properties that were
previously enforced only by whoever remembered to type them into
`Package.swift`.

`check-embedded.sh` gained a real size gate the same day (`8c9d1c7`, the
evidence ADR 0009 had been citing without it existing). It reads
`scripts/embedded-size-baseline.txt`, which pins a compiler revision, a byte
count, and a tolerance percent, and it fails if the artifact moves outside the
band **in either direction** or if the baseline's pinned revision is not the
compiler in use — so a toolchain bump fails this gate until the baseline is
deliberately re-measured.

**The `run-gama` skill is tracked twice and the docs gate enforces parity.**
`.agents/skills/run-gama/{SKILL.md,driver.sh}` and
`.claude/skills/run-gama/{SKILL.md,driver.sh}` must stay equivalent after the
gate normalizes each entry-point path to `<run-gama-skill>`. Editing one mirror
alone fails `check-docs.sh` — a documentation gate failing on a shell script,
which reads as an unrelated break. Change both, or neither.

Run tests directly (single test, filtered) — must use a scratch path outside
iCloud:

```bash
unset TOOLCHAINS
swiftly run swift test \
  --scratch-path /private/tmp/gama-framework-swiftpm --filter <TestNamePattern>
```

(`/usr/bin/xcrun --toolchain org.swift.65202608211a swift test …` is the
equivalent explicit form the scripts use.)

**Redirecting gate scratch: the variable is `GAMA_SCRATCH_ROOT`, not
`SCRATCH_ROOT`.** Eight scripts (`check-wasm.sh`, `check-linux.sh`,
`check-linux-leaks.sh`, `check-c-abi.sh`, `check-android.sh`,
`check-android-emulator.sh`, `check-doc-coverage.sh`, `bundle-web.sh`) derive
scratch from `GAMA_SCRATCH_ROOT` → `RUNNER_TEMP` → `TMPDIR` → `/tmp`; a bare
`SCRATCH_ROOT` is silently ignored and the run lands in the shared default.
`check-apple.sh` reads its own `GAMA_APPLE_SCRATCH_PATH`; see the other
`GAMA_*_SCRATCH_PATH` / `GAMA_*_OUTPUT` names in the scripts.

**Toolchain paths are derived, never written down.** `scripts/lib/toolchain.sh`
resolves the pinned snapshot from `Toolchains.toml`'s `[snapshot].xctoolchain`
under `$HOME`, and `check-wasm.sh`, `check-linux.sh`, `check-android.sh`,
`check-embedded.sh`, and `bundle-web.sh` source it. `check-toolchain-pins.sh`
now **fails on any checked-in `/Users/<name>/` or `/home/<name>/` path under
`scripts/`**, because those five previously defaulted to one developer's home
directory: correct on exactly one machine, silently wrong everywhere else,
inside gates meant to fail closed. CI never reached them, since
`ci-install-swift-snapshot.sh` exports `GAMA_SWIFT_64`, which is why only a
second developer would have found them. Two caveats:
`swiftc` aborts with `couldNotFindTmpDir` if the `TMPDIR` you pass does not
exist, so `mkdir -p` it first; and **`check-mlir.sh` hardcodes
`/private/tmp/gama-framework-swiftpm` with no override — the same path the
single-test command above recommends**, so a filtered `swift test` and a
concurrent MLIR gate collide. `check-apple-platforms.sh` likewise hardcodes
`/private/tmp/gama-<platform>-derived`. Give each session its own root when a
peer may be running gates.

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

**`#expect` cannot read a bare property off a `~Copyable` host.**
`#expect(host.needsFrame)` does not compile: the macro expands to
`__checkPropertyAccess`, which requires `Copyable`, and the diagnostic names
that helper rather than the property — so it reads as an unrelated failure.
Bind first (`let dirtyAfter = pump.needsFrame; #expect(dirtyAfter)`); every
`needsFrame` assertion in `GamaTests` already has this shape. Comparisons
(`#expect(host.duplicateIDs == [...])`) take a different overload and are
fine.

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

- **GamaCore** — scenes, views, identity, state, layout, events,
  `FrameHost`, the per-host `@Reactive` state store it owns
  (`ReactiveState.swift`), and `CompletionStatus` (`Completion.swift`): a
  declared process outcome, never inferred from quiescence. Embedded-Swift-safe:
  stdlib only. `check-boundaries.sh`
  rejects any import of Foundation, AppKit, UIKit, Darwin, Glibc, WinSDK, or
  Synchronization in GamaCore *and* GamaPlugin, and rejects process-global
  registries anywhere. `FrameHost` and `AppRuntime` are `~Copyable`: each
  host uniquely owns focus, actions, `@Reactive` state, subscriptions, dirty
  state, and frames; out-of-band changes go through the host's
  `SubscriptionContext`, a bound `@Reactive` write, or explicit
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
- Every Swift target builds in Swift 6 language mode with the `ExistentialAny`,
  `MemberImportVisibility`, and `InternalImportsByDefault` upcoming features
  (`strictCore` in `Package.swift`; the C-only `GamaTUISignal` and
  `GamaEmbedABI` carry no Swift settings), so a member that compiles in one
  file is rejected in another until that file imports the defining module
  itself, and a module whose types appear in a public declaration must be
  `public import`ed (the compiler also rejects an unused `public import`).
  Shipped library and macro targets additionally use `strictLibrary`: strict
  memory safety with the `StrictMemorySafety` group promoted to an error, so
  every unsafe operation is spelled `unsafe` at its site and a type with
  unsafe storage but a safe API is `@safe`. Executables and `GamaTests` stay
  on `strictCore` (ADR 0012 records the measured counts). `GamaAppleUI` adds
  `InferIsolatedConformances`; `GamaWASM` adds experimental `Extern`.
- **GamaMacros / GamaMacrosImpl** — optional `@Component`, `@Reactive`, `#rgb`
  sugar; the impl is a host-side compiler plugin. swift-syntax is the only
  package dependency, pinned by revision, build-time only — nothing from it
  links into shipped products (zero-runtime-dependency constraint).
- **GamaDraw** — platform-free rasterizer shared by every backend: CellBuffer
  (double-buffered grid + ANSI diff), CellPainter (IR → cells), DrawList
  (cells → vector commands + versioned little-endian binary, magic `GAMA`,
  version 1), and `AccessibilitySnapshot` (`DrawList` → text plus per-line
  frames). Two presentation families sit on the same buffer and must not be
  unified: `CellPresenter` (`StreamPresenter.swift`) is mutating and swaps
  planes (`AnsiPresenter` / `StreamPresenter`, TUI only); `CellSerializer`
  (`CellSerializer.swift`) is non-mutating and does not swap
  (`DrawListSerializer` for Embed/Apple, `HTMLSerializer` in GamaWASM).
  Accessibility is therefore a *portable* concern computed here, not
  an Apple-only one: `AccessibilitySnapshotTests` pins the platform-free
  derivation and `AppleHostAccessibilityTests` pins the AppKit/UIKit bridge in
  `Sources/GamaAppleUI/GamaHostAccessibility.swift`.
- **Backends** translate events in and present `DrawList` out; they never fork
  application semantics. GamaTUI (POSIX termios + Windows Console VT; its
  signal handling lives in the **C-only** `GamaTUISignal` target so that
  dispositions, restore bytes, and `sig_atomic_t` latches never run Swift
  runtime code in async-signal context — do not reimplement it in Swift;
  `AdaptiveSurface.swift` adds `SurfaceMode` / `StreamRenderer` /
  `App.runAdaptive()` so a TTY gets `TUIRenderer` and a pipe gets plain
  lines with no termios, overridable by `--gama-plain` / `--gama-tui`;
  an input-less stream run ends at the first quiescent frame unless the
  app declared `CompletionStatus`; `gama-demo` still drives `TUIRenderer`
  itself because of its plugin loop — use the `run-gama` skill, not a
  redirected `swift run`),
  GamaAppleUI (`@MainActor` NSView/UIView via CoreGraphics), GamaAppleShell
  (NSApplication/NSWindow ownership, multi-window and per-shell command
  routing; compiles to an inert target without AppKit — it is the one
  backend that renders auxiliary scenes), GamaWASM
  (browser reactor, inert stubs off wasm32, experimental `Extern` feature
  scoped to this target only; `WebHost/` holds the page and JS glue the web
  demo is served from. It publishes **two export tiers, not one**:
  `gama_web_v1_*` and the argument-compatible status-reporting
  `gama_web_v2_*`, which fails closed with `-1` before `GamaWeb.install` and
  returns `-2` from `gama_web_v2_key` for an invalid key code — a change to
  either tier is a public-ABI change, see `docs/backends/WASM.md`),
  GamaEmbed +
  GamaEmbedABI (context-owned flat C ABI `gama_embed_v1_*`; C header and
  ownership rules in `Sources/GamaEmbedABI/include/GamaEmbed.h`; static so the
  entry points fold into the host binary), GamaMLIR (deterministic textual
  `gama` dialect emitter — not a Swift MLIR frontend).
- C and WASM symbols remain versioned and separately namespaced.
- **`gama-web-demo` deliberately keeps the macro plugin out of the wasm32
  dependency graph, and that dependency has flipped more than once
  (`79cccd3` added `GamaMacros`, `5dbdad8` removed it again).**
  `GamaWebDemo` depends on `GamaCore` and `GamaWASM` only, declaring its
  counter with a direct `ReactiveSlot` instead of `@Component`/`@Reactive`;
  its `--export=` linker flags are target-local *and* `.when(platforms:
  [.wasi])` so SwiftPM cannot forward them to the host-side `GamaMacrosImpl`
  build. Read the `GamaWebDemo` target block in `Package.swift` before
  changing either — never a memory of it. Rationale: `docs/backends/WASM.md`
  and ADR 0011.
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

`bundle-macos.sh` closes with a four-step verification block — `plutil
-lint`, ad-hoc `codesign`, `codesign --verify --deep --strict`, then launching
the bundled app with `--smoke` — so a packaging change can fail on app startup
rather than on the bundling, and the ad-hoc signature is local-launch evidence
only (`release-macos.sh` is the Developer ID + notarization path). The smoke
step is also why `GamaAppleDemo` depends on `GamaAppleUI`
and `GamaDraw` directly: the smoke path reads
`GamaHostView.currentDrawList.commands`, and `MemberImportVisibility` requires
importing each declaring module.

## @Reactive state is per-surface

A scene's content closure runs **on every frame**, and building a
`@Reactive` component inline inside it is now the correct shape:
`Window("Counter", id: "main", role: .primary) { Counter() }` keeps its
state, because `@Reactive` no longer lives in the component instance.
`@Reactive var x` expands to a `ReactiveSlot` peer, and the `render(in:)`
that `@Component` synthesizes binds each slot to the owning `FrameHost`'s
per-host state store, keyed by `(NodeID, slot index)`. A fresh instance each
frame binds to the same host-owned signal. `Sources/GamaDemo/main.swift`
builds `CounterPanel()` inline in `DemoApp.scenes`; a hoisted instance still
works and writes per surface, so no migration is needed.

The contract is two words: **`@Reactive` is per-surface; a `Signal` on the
`App` is shared.** Two windows of one `WindowGroup` get independent
`@Reactive` state; a `Signal` stored on the app is one instance behind all of
them (`Signal` still requires one host at a time, never concurrent hosts).
Raw `Signal` stored properties inside components are unsupported — convert
them to `@Reactive` and pass `_name.binding()` to `TextField`/`Toggle`.

Two compile errors keep the binding from being skipped silently:
`reactive.requires-component` (`@Reactive` outside a struct marked
`@Component`, including in a class) and `component.render-collision` (a
hand-written `render(in:)` beside `@Reactive` properties; synthesis is
skipped). At runtime `FrameHost.transientStateIDs` lists nodes whose reactive
storage was replaced at the same `(NodeID, slot)` key since the previous
frame, such as a slot value-type change. It does not report new or removed
keys, or positional `ForEach` reorders that reuse storage for different
elements. An empty diagnostic does not establish element-stable identity.
The store sweeps once
per `pump` after the final build, so a subtree that stops rendering releases
its state; `IdentifiedForEach` and `.stateScope(_ id: NodeID)` pin a subtree
to an explicit identity where structural keying is wrong. Host-less
rendering (`BuildContext()` with no store, as `gama-demo --emit-mlir` uses)
keeps instance-local storage. `State<Value>` is unchanged.

Every host-owned signal observes the host's dirty flag, so an out-of-band
write to bound `@Reactive` state requests a frame without `observe()`.
`ViewStateIdentityTests` (`Tests/gamaTests/ViewStateIdentityTests.swift`)
pins the model; `ReactiveStateLifetimeTests` (in
`Tests/gamaTests/MacroUsageTests.swift`) pins the hoisted shape. ADR 0011
(`docs/adr/0011-reactive-state-is-per-surface.md`) records the decision and
the argued `WindowGroup` behavior flip.

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
