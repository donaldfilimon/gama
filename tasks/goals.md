# Goals

## Current objective

Keep Gama a portable, retained Swift UI framework whose documentation and
evidence match the exact source, toolchain, and acceptance matrix.

The accepted foundation designs are implemented. Current maintenance keeps
state ownership, diagnostics, and documentation aligned with that foundation;
[`todo.md`](todo.md) records the delivery requirements, manual and
credential-gated acceptance, and deferred product scope. New product scope
needs a new accepted design. Extending strict memory safety to executables
and the test target remains a separate decision documented in ADR 0012.

## Toolchain selection and 6.5-dev spelling audit
status: in_progress

- Closed a false green in `scripts/check-toolchain-pins.sh`. It enumerated
  five scripts while ten hardcode the pinned toolchain id, so `bundle-macos`,
  `check-boundaries`, `check-doc-coverage`, `check-portable-symbols`, and
  `profile-apple-host` could go stale while the gate still printed OK. It now
  discovers every `GAMA_TOOLCHAIN_ID` default and rejects any digit-leading
  `org.swift.*` literal under `scripts/` that is not the pin. Verified by
  mutation in both directions; `check-boundaries.sh`, which chains it, is
  green. Local evidence only, on top of an already-unpushed line.
- **Re-probed 2026-09-06 against the pinned compiler, not against proposal
  titles, and the answer is still no migration.** Shipped sources carry three
  underscored attributes: `@_cdecl` (17), `@_extern` (7), `@_exported` (2).
  Measured, one at a time:
  - `@extern` unprefixed **does not exist** — `error: unknown attribute
    'extern'`. `@_extern` still requires the experimental `Extern` feature the
    package already scopes to `GamaWASM`. No migration is available at all.
  - `exported import` unprefixed **does not parse**. No migration available.
  - `@c(identifier)` **works**, and accepts the real ABI names — `@c(gama_web_v2_frame)`
    emits exactly `_gama_web_v2_frame`. But the symbol counts settle it:
    `@c` emits **one** symbol while `@_cdecl` emits **two**, the C name plus
    the Swift-mangled `_$s…`. Migration is therefore an ABI *narrowing* on
    `gama_embed_v1_*` and `gama_web_v1_*`/`v2_*`, which this repository's own
    rule treats as a public-ABI change.
  Nothing in `Sources/`, `Examples/`, `WebHost/`, or `scripts/` references a
  mangled Swift symbol, and the C header publishes 11 `gama_embed_v1_*` names,
  so the removal would very likely be harmless in practice. "Very likely
  harmless" is not a reason to narrow a shipped versioned ABI when the change
  buys only the deletion of an underscore and no defect motivates it.
- Audited the 6.5-dev spellings against the pinned compiler rather than
  against proposal titles. No source migration is warranted now: `@_extern`
  has no unprefixed form, and the one available migration is a versioned-ABI
  change recorded under deferred scope in [`todo.md`](todo.md).
- Hosted proven at `0d4cf12`, re-verified from run state 2026-09-06: run
  `34049182287` completed with all six required jobs green. When this line was
  first written that run was still `in_progress`, so the claim ran ahead of its
  evidence by a few minutes — check `gh run view`, never a watcher's exit code.
  The gate change went out as PR #82, cherry-picked
  onto `origin/main` so it could be reviewed apart from PR #81, and all six
  required acceptance jobs passed on the updated head. The hole it closes was
  independently reproduced by mutation: with a stale id planted in
  `check-boundaries.sh` the previous gate exited 0 and printed OK, while the
  current one exits 1 and names the file.

## Adaptive terminal surface
status: done

- **Hosted proven 2026-09-06.** PR #83 merged as `98c150d` with all six
  required acceptance jobs green at its head `3f180f1`, whose tree is
  byte-identical to the merge commit's — so the evidence covers the exact
  integrated tree rather than only the branch. Phases 1-4 are shipped and
  proven; phase 5 is closed unbuilt with a designed successor that is not
  implemented, recorded below and in its own spec. Closing this goal does not
  claim `CellSerializer`.

- Phases 1-3 implemented and locally verified 2026-09-06: `CompletionStatus`
  and the completion signal in `GamaCore`, `CellPresenter` plus
  `AnsiPresenter`/`StreamPresenter` in `GamaDraw`, and `SurfaceMode`,
  `StreamRenderer`, and `App.runAdaptive()` in `GamaTUI`. An application that
  adopts `runAdaptive()` renders a live TUI on a terminal and emits plain
  changed rows when redirected, ending on a declared completion status. Its
  stream layout is fixed at 80 columns, so a line wider than that wraps
  through `CellPainter`; honoring `COLUMNS` belongs to phase 4.
- An end-to-end probe outside the repository caught a hang the unit tests
  could not: an input-less surface with no declared completion never
  terminated. Fixed with `Renderer.waitsForInput` (defaulted `true`, so no
  existing backend changes). Verified at the process boundary: piped, the
  probe now exits `0` with its content on stdout; with a declared failure it
  exits `3` and puts the message on stderr; under a pty it selects
  `TUIRenderer` and emits cursor-positioning ANSI. 20 new Swift
  Testing cases in 3 suites; the suite is 291 in 53. Local only: no hosted
  matrix has run against this work, so no ledger row may be promoted.
- The phase 5 spike ran and rescoped that phase. One `CellBuffer`-rooted
  shape fits `GamaTUI`, `GamaWASM`, and `GamaEmbed`; `GamaAppleUI` is excluded
  because it mutates a retained view rather than producing an output value.
  The macOS AppKit host row therefore no longer resets.
- Phase 4 implemented 2026-09-06 as an emitted-line channel rather than the
  view-tree `StreamOutput` the design sketched. `RenderNode` is an indirect
  enum every backend switches on exhaustively, so a new case would have
  rippled through layout, painting, MLIR, WASM, and Embed. More importantly a
  chronology is event-shaped: a line happens once, while a view node is
  re-evaluated every frame, so deriving one from the tree would replay lines
  or need a second diff. `SubscriptionContext.emit(_:)` is exactly-once by
  construction. `App.connect(_:)` (defaulted, so existing apps are
  unaffected) hands the application its channel, which also closed a real gap:
  before it, an app launched through `runAdaptive()` could neither report an
  outcome nor emit anything.
- Verified end to end at the process boundary with one declaration and one
  binary: piped it emits `deploy: step 1/10 building` and exits `2` with the
  message on stderr; under a pty the same binary renders the grid
  (`[####------] 3/10`, cursor-positioning ANSI) and the emitted lines are
  correctly absent, because grid backends ignore them.
- Open: phase 5 (conform `GamaWASM` and `GamaEmbed` to `CellPresenter`).
  Umbrella record in
  [`2026-09-06-adaptive-terminal-surface-design.md`](../docs/superpowers/specs/2026-09-06-adaptive-terminal-surface-design.md);
  phases 1-3 in
  [`2026-09-06-adaptive-terminal-core-design.md`](../docs/superpowers/specs/2026-09-06-adaptive-terminal-core-design.md).
- Phase 5 closed without implementation. A closer review reversed the spike:
  `GamaWASM` and `GamaEmbed` never call `presentDiff()` and read the back plane
  wholesale, so `CellPresenter`'s "then swaps the buffers" contract is false
  for them; and both reach the grid through `HostPump.advance(into:emit:)`,
  whose `emit` takes a **borrowing** `CellBuffer`, so no `inout` access can be
  formed and a conformance would have zero call sites. Naming that family
  honestly needs a different, non-mutating `borrowing CellBuffer -> Output`
  abstraction, which is new design rather than this phase.
- Correction the same review produced: `DrawList/C ABI` is **Locally proven**,
  not hosted proven, and `Embedded core` is locally compile/link proven. An
  earlier revision of the spec and of this ledger overstated both. Among the
  backends phase 5 would have touched, only WebAssembly/browser and Android/JNI
  carry hosted rows.
- `AnsiPresenter` had no production call site when it shipped, which made the
  protocol a claim rather than a seam. `TUIRenderer` now presents through it.
- Phase 5's successor is designed but **not implemented**, spec at
  [`2026-09-06-cell-serializer-design.md`](../docs/superpowers/specs/2026-09-06-cell-serializer-design.md):
  a non-mutating `CellSerializer` (`func serialize(_ buffer: borrowing
  CellBuffer) -> Output`) naming the wholesale family, with two conformances,
  `DrawListSerializer` and `HTMLSerializer`. Grounded by re-reading the code
  rather than the earlier notes: neither `GamaWASM` nor `GamaEmbed` ever swaps
  or calls `presentDiff`, and `advance(into:emit:)` hands them a **borrow**, so
  no `inout` access can be formed — the two reasons `CellPresenter` cannot span
  them are one fact stated twice.
- A third conformance was proposed and withdrawn before anything was built.
  `AccessibilitySnapshot`'s only production consumer is `GamaAppleUI`, deriving
  it from a retained view's `currentDrawList`, not from a borrowed buffer; and
  `GamaWASM` has no Swift accessibility path, the gate's assertion being in the
  browser driver. An `AccessibilitySerializer` would have had zero call sites,
  repeating the `AnsiPresenter` defect recorded directly above it.
- **Implemented 2026-09-06**, and materially changed by an independent design
  review before it landed. Three factual errors were found and corrected. The
  spec claimed a one-byte HTML change would break the browser marker and an
  encoding change would break `check-c-abi.sh`; verified directly, the marker
  reads `root.textContent` through a regex and `Examples/CEmbed/main.c` checks
  length plus the `GAMA` magic but no draw command, so **both claims were
  false** — the failure this repository's evidence policy exists to prevent.
  Nothing pinned byte-identical HTML at all, so a test now does.
- The review also showed `GamaAppleUI` belongs in the family:
  `GamaHostView.swift:242` has the identical shape to `GamaEmbed`, and the
  exclusion had been inherited from the phase 5 spike whose `inout`/swap
  grounds a `borrowing` protocol does not have. Including it is what gives
  `DrawListSerializer` more than one call site.
- Open and stated rather than papered over: nothing in the tree is generic over
  `CellSerializer`, so it constrains conformers, not consumers.
- Verified locally: `check-apple` (304 tests in 55 suites), `check-wasm`,
  `check-c-abi`, `check-boundaries`, `check-docs`, `check-doc-coverage`, all
  exit 0. `check-wasm` is the only gate that type-checks the WASM call site.

## Evidence-first behavior-preserving refactor
status: done

- **Hosted proven 2026-09-06.** The slice `dc7e847` and both ledger commits
  are ancestors of `98c150d`, integrated through PR #83 rather than the
  standalone PR the handoff report proposed. All six required jobs green.
  Candidates 3-5 stay not recommended and are deliberately not delivered.

- Audit delivered 2026-09-06 against `origin/main` `0d4cf12`, ten commits past
  the brief's `bc2fe4d` reference snapshot. Module map, five candidates, and a
  recommended first slice are in [`todo.md`](todo.md).
- First slice approved and delivered 2026-09-06 as `dc7e847`: gate scripts
  derive the pinned toolchain from `Toolchains.toml` through
  `scripts/lib/toolchain.sh` instead of defaulting to one developer's home
  directory, and `check-toolchain-pins.sh` fails on any checked-in home path
  so the class cannot return. Behavior preserved: the derived path is
  byte-identical to the removed literal on this machine. Eleven of the
  thirteen `check.sh` gates green (two NOT RUN for missing local
  prerequisites), including the four rewired scripts and `check-boundaries`,
  which chains the pin gate. `bundle-web.sh` is the fifth rewired script and
  is not a gate at all — it is the Pages deploy path, syntax-checked only.
  Local evidence only; the six-job matrix has not run.
- The slice shipped **narrower than approved**, on evidence. It also proposed
  adding `unset TOOLCHAINS` to the nine scripts lacking it, on this
  repository's documented claim that a stray value overrides explicit pins.
  Measured, it does not: `TOOLCHAINS` overrode a bare `xcrun swift` but not
  `xcrun --toolchain <id>`, and not the `swiftly` shim, and no script invokes
  swift without the flag. `CLAUDE.md` was narrowed to what reproduces rather
  than nine scripts being changed to satisfy a claim that does not.
- Candidates 3-5 (`GamaHostView` split, `Primitives.swift` size,
  `Terminal.swift` platform split) remain **not recommended**: each is a file
  split with no demonstrated defect, and candidate 3 carries the highest risk
  against hosted-proven AppKit for a presentational benefit.

## Capability-ledger honesty
status: in_progress

- **Full row audit delivered 2026-09-06.** Every one of the seven rows that
  named a commit was stale: the files each row's claim depends on had changed
  since the commit it named. Five (`Scene-first core`, `Strict memory safety`,
  `WebAssembly/browser`, `Android/JNI`, `Per-surface @Reactive`) were re-proven
  by the later merges, so they are re-pointed to `98c150d` rather than
  downgraded, each carrying a note saying what changed and why the old anchor
  failed. Two carried stale *measurements* and could not simply be re-pointed:
  the packaged-wasm row's 9,297,539-byte artifact figure is **removed**, since
  both the bundler and the bundled source changed and no re-measurement was
  taken; the Embedded row is re-measured at **641,464 bytes** (from 636,792),
  and its claim that `5dbdad8` is "unpushed" is corrected — that was true when
  written and is now false.
- **Unanchored rows surveyed 2026-09-06.** Of 20 table rows, 13 named no
  commit. Three of those asserted **Hosted proven with neither a commit nor a
  run id** — `Core/builders/layout/drawing`, `macOS multi-window shell`, and
  `Plugin runtime + capability model (Tier 1)` — the weakest claims in the
  file, since an unanchored claim cannot even be checked for staleness. All
  three are now anchored to `98c150d`.
- One row was overstating its own coverage: `DrawList/C ABI` claimed
  "randomized/malformed codec tests". Verified — **no randomized or fuzz codec
  test exists anywhere under `Tests/`**. The word is removed rather than a test
  invented to justify it.
- Six rows use phrases outside the declared vocabulary (`locally compile
  proven`, `locally cross-compile proven`, `locally runtime proven`, `locally
  compile/test proven`). On inspection these are **narrower** than "Locally
  proven", not looser, so the honest fix was to declare them in the vocabulary
  section as restrictions rather than normalize them away and lose precision.
- **The defect recurred within this session, from my own commits, and that is
  the strongest argument for mechanizing it.** `7d4feb7` anchored rows to
  `98c150d` while `30afe99`, `a4c7a5c`, and `eeb2426` had already changed the
  sources four of those rows describe — `GamaDraw/CellSerializer.swift`,
  `GamaAppleUI/GamaHostView.swift`, `GamaEmbed/CInterface.swift`, and
  `GamaWASM/WASMHost.swift`. Hand-auditing fixed the ledger and hand-editing
  re-broke it inside a few hours, with all gates green throughout. Those four
  rows now declare the drift explicitly rather than carrying a hosted claim
  that does not describe the working tree.
- Still open, and genuinely so: the remaining ten unanchored rows are
  local-evidence claims whose anchor would have to be a local run rather than a
  hosted commit, and `Windows console` has **no check script at all** — its job
  is inline in `.github/workflows/ci.yml`, so `scripts/check.sh` cannot prove
  it locally by any means.

- Corrected `docs/Capabilities.md` 2026-09-06. Its Evidence snapshot named
  `bc2fe4d` as the current `origin/main` tip while the tip was `0d4cf12`,
  thirteen commits later, and the per-surface `@Reactive` row still attached
  its hosted claim to `77812d99` while describing four behavior changes made
  after that merge. Both are now stated against the commits that actually
  carry the evidence: the snapshot names run `34049182287` at `0d4cf12`, and
  the row names run `34048029135` at `7d6e2fb`, whose six required jobs were
  green first-attempt and which contains all four changed commits. The row's
  "locally proven at unpushed `5dbdad8`" caveat is removed because it is no
  longer true.
- The recorded suite size was wrong in two places and both were low: the row
  said 266 tests in 49 suites and the ledger said 269. Measured, it is **299
  in 54**. Local gates re-run for this slice: `check-apple.sh`,
  `check-docs.sh`, `check-doc-coverage.sh`, all exit 0.
- Open: the remaining rows still keyed to `77812d99` have not been audited one
  by one against `0d4cf12`; this slice corrected the two demonstrably stale
  claims, not the whole table.

## Delivered foundation

The current `main` line includes the Swift 6.5-dev umbrella, scene-first core,
shared frame pump, non-Sendable host state, noncopyable hosts and terminal
ownership, per-surface identity-keyed `@Reactive` state, strict memory safety
on every shipped library and macro target, explicit import access levels on
every Swift target, Tier-1 plugins, Apple shell, TUI, Wasm, C/Android
embedding, MLIR, packaging,
accessibility derivation, deterministic performance evidence, and full public
DocC coverage.

The source of truth for what is proven is
[`docs/Capabilities.md`](../docs/Capabilities.md). The full local driver has 13
fail-closed gates in `scripts/check.sh`; hosted proof is the six-job "Gama
acceptance" workflow for the exact pushed commit. Manual UI, accessibility,
credentialed release, physical-device, and physical-board acceptance remain
separate evidence layers.

## Ledger rules

- Keep only current work here and in `todo.md`; Git and dated design records
  retain completed history.
- Do not copy volatile test counts, artifact sizes, run IDs, or branch names
  into this ledger unless they are required to explain an unresolved blocker.
- When a claim changes, update the capability guide or owning design record
  once and link to it instead of duplicating the prose.
- Never promote local, hosted, generated-artifact, or manual evidence into a
  stronger layer.
