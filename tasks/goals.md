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
- Audited the 6.5-dev spellings against the pinned compiler rather than
  against proposal titles. No source migration is warranted now: `@_extern`
  has no unprefixed form, and the one available migration is a versioned-ABI
  change recorded under deferred scope in [`todo.md`](todo.md).
- The gate change is not covered by the eleven-gate run recorded in
  [`todo.md`](todo.md): that run was at `5dbdad8` and this change is later than
  it. `check-toolchain-pins.sh` and `check-boundaries.sh`, which chains it, are
  green locally; the remaining gates have not been re-run against it.

## Adaptive terminal surface
status: in_progress

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
- Open: phase 4 (author-declared `StreamOutput`) and phase 5 (conform
  `GamaWASM` and `GamaEmbed`). Both need their own spec before execution.
  Umbrella record in
  [`2026-09-06-adaptive-terminal-surface-design.md`](../docs/superpowers/specs/2026-09-06-adaptive-terminal-surface-design.md);
  phases 1-3 in
  [`2026-09-06-adaptive-terminal-core-design.md`](../docs/superpowers/specs/2026-09-06-adaptive-terminal-core-design.md).
  Phase 5 would reset the WebAssembly/browser and DrawList/C ABI rows, which
  are hosted proven at `bc2fe4d`, until a fresh six-job run covers them.

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
