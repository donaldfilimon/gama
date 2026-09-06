# Adaptive terminal surface (umbrella)

Status: Phases 1-3 implemented and locally verified 2026-09-06; phases 4-5
proposed. The phase 5 spike has been run and its answer is recorded below,
which rescopes that phase and reduces its evidence cost. No hosted proof
covers any of this: local gates are not the platform matrix.

## Problem

Gama drives native Apple, WebAssembly, C/Android, Embedded, and MLIR edges from
one retained core, and its terminal edge renders an interactive cell grid. It
has no answer for the same program running non-interactively. A Gama binary
piped into another process, redirected to a file, or run in CI still emits a
grid of box-drawing characters and cursor movements, and it has no way to say
whether it succeeded.

"CLI" appears twice in the repository, both times as a deferred *distribution*
veneer in [`Packaging.md`](../../Packaging.md) and
[`todo.md`](../../../tasks/todo.md). That is a different thing from the surface
described here, and this document does not address it.

## Decisions

Taken during design on 2026-09-06 and treated as settled for the phases below.

1. **Extend Gama rather than build a separate library.** Native app, web, and
   TUI already run from one core; the gap is one surface, not four.
2. **Adaptive, not a separate mode.** One binary renders a live TUI on a TTY
   and plain, pipeable output when stdout is not a TTY. The author writes one
   `App`.
3. **Derive by default, override where it matters.** Every existing Gama
   application gains usable non-TTY output with no source change, from frame
   diffing. Authors who care about output quality opt into a declared stream
   representation.
4. **Self-driving with explicit completion.** Non-TTY runs take no input
   events. The application signals completion with a status that becomes the
   process exit code. Completion means completion on both paths; TTY and pipe
   differ only in presentation.
5. **Logic in `GamaDraw`, selection in `GamaTUI`, no new target.** See
   *Module placement*.
6. **Introduce the presenter abstraction additively, then refactor.** The
   protocol arrives without changing any existing call site (phase 2); the
   existing backends are converted to it separately (phase 5).

## Non-goals

- A `gama` scaffolding or build command. That is the packaging veneer.
- Argument parsing, subcommands, or help-text generation. That is
  swift-argument-parser's domain and shares no code with the retained pipeline.
- Reading stdin as an input-event source. Considered and rejected: it invents a
  second input vocabulary beside key and pointer events.
- Any Windows claim. The Windows console row is **Blocked** in
  [`Capabilities.md`](../../Capabilities.md) for want of a 6.5-dev snapshot, and
  this work does not unblock it.

## Module placement

The load-bearing choice is that the frame-to-lines derivation is platform-free
and therefore belongs in `GamaDraw`, beside the differential ANSI presenter it
parallels (`CellBuffer.presentDiff()`,
`Sources/GamaDraw/CellBuffer.swift:146`). Once it lives there, `GamaTUI` keeps
exactly one responsibility — own the terminal and present to it — and merely
selects between two presenters. No second backend target is required, and the
hard part is testable with no I/O.

| Module | Addition | Rationale |
| --- | --- | --- |
| `GamaCore` | `CompletionStatus`; completion signal on `SubscriptionContext` | `Int32` and `String` need no Foundation, so the stdlib-only boundary holds |
| `GamaCore` | Opt-in `StreamOutput` on components | A view-tree concern, so it belongs beside `body` |
| `GamaDraw` | `StreamPresenter`; `Presenter` protocol both it and the ANSI path conform to | Platform-free; parallels `presentDiff()` |
| `GamaTUI` | `isatty` detection and presenter selection | The module that already owns `STDOUT_FILENO` |

`GamaCore` and `GamaPlugin` remain stdlib-only and `check-boundaries.sh`
continues to enforce that. Nothing in this design routes an OS capability
through the portable core.

## Spike result: the abstraction fits three of four

Run 2026-09-06, before phase 5 was attempted. The question was whether one
shape spans the existing backends. It spans three of them, and the fourth is
excluded for a principled reason rather than an awkward one.

| Backend | Roots on | Emits | Fits |
| --- | --- | --- | --- |
| `GamaTUI` | `CellBuffer` | `String` (ANSI) and `[String]` (lines) | Yes, conformed in phase 2 |
| `GamaWASM` | `CellBuffer` | `String` (HTML grid, `WASMHost.grid(from:)`) | Yes |
| `GamaEmbed` | `CellBuffer` | `[UInt8]` (`DrawList.from(painted).encode()`) | Yes |
| `GamaAppleUI` | `DrawList` | mutates a retained view; returns nothing | No |

`GamaAppleUI` is not a producer. Its frame path assigns `currentDrawList` and
mutates retained view state, so there is no output value for an
`associatedtype Output` to name. Forcing it to conform would mean inventing a
return value that nothing consumes. It stays out of the family by design.

**Phase 5 is therefore rescoped to `GamaWASM` and `GamaEmbed`.** Because
`GamaAppleUI` is excluded, the macOS AppKit host row does not reset, which
removes the largest single piece of the evidence cost recorded below.

The original risk, retained for the record:

Phase 5 assumed one `Presenter` shape spans the existing backends. Before the
spike that was not established:

| Backend | Consumes | Emits | Update model |
| --- | --- | --- | --- |
| `GamaTUI` | `CellBuffer` | ANSI `String` | differential |
| `GamaAppleUI` | `DrawList.commands` | draws into a retained view | incremental |
| `GamaWASM` | `DrawList` | HTML through an `@_extern` host call | full replace |
| `GamaEmbed` | `DrawList` | versioned little-endian binary over a C ABI | full encode |

These differ in input type, output type, and whether they are differential or
wholesale. A protocol spanning all four risks either accumulating associated
types until it constrains nothing, or forcing contortions into code that is
currently hosted proven. Phase 5 therefore begins with a spike answering one
question: does a single shape fit all four without contorting any of them? A
negative answer is a useful result and narrows phase 5 to the subset it fits.

## Evidence cost

Phase 5 as rescoped modifies `GamaWASM` and `GamaEmbed` only. The
WebAssembly/browser and DrawList/C ABI rows in
[`Capabilities.md`](../../Capabilities.md) are **Hosted proven** at merge commit
`bc2fe4d`. By the ledger's own rule that proof does not transfer across the
change: on merge those rows drop to *Implemented* until a fresh six-job
acceptance run passes at the new merge commit. The macOS AppKit host row no
longer resets, because the spike excluded `GamaAppleUI` from the refactor.

Phases 1 through 4 add new surface without altering existing backend behavior
and carry no such reset, but still require the full matrix before integration.

## Phases

Each is independently shippable and needs its own spec and plan.

1. `CompletionStatus` in `GamaCore`. No dependents.
2. `StreamPresenter` and the `Presenter` protocol in `GamaDraw`, introduced
   additively with no existing call site changed.
3. `isatty` detection and presenter selection in `GamaTUI`. **The adaptive
   binary works end to end at the close of this phase.**
4. Opt-in `StreamOutput` for authors. Output-quality upgrade.
5. Spike, then convert `GamaAppleUI`, `GamaWASM`, and `GamaEmbed` to
   `Presenter`. Gated on the spike; carries the evidence reset above.

Phases 1 through 3 are specified together in
[`2026-09-06-adaptive-terminal-core-design.md`](2026-09-06-adaptive-terminal-core-design.md).
Phases 4 and 5 are specified when reached.
