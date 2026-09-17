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

**A second, deeper review then reversed this.** The table above compares what
each backend *roots on*, which is the wrong question. What matters is how each
one reconciles:

- `GamaWASM` and `GamaEmbed` never call `presentDiff()`. Grepping the tree, its
  only callers are `GamaTUI`, `GamaDraw`'s own presenters, `GamaBench`, and
  tests. Both read the back plane wholesale, so `forceFull` stays `true` for
  the buffer's lifetime and `front` is dead storage: they use `CellBuffer` as a
  **single-buffered raster**. `CellPresenter`'s contract says it reconciles
  "then swaps the buffers", which is simply false for them. An honest conformer
  would have to call `presentDiff()` and discard an ANSI string every frame
  purely to satisfy a clause it does not want.
- Mechanically it cannot be additive either. Both reach the buffer through
  `HostPump.advance(into:emit:)`, whose `emit` receives a **`borrowing`**
  `CellBuffer` by documented contract, so no `inout` access can be formed
  inside it. A conformance added without changing that contract would have
  **zero call sites**: dead public surface carrying doc-coverage obligations.

**Phase 5 is therefore not done, and should not be done as specified.** If the
family is worth naming at all, the honest abstraction is a different one: a
non-mutating `borrowing CellBuffer -> Output` over *wholesale serialization of
a painted grid*, which `HTMLSerializer.grid(from:)` and
`DrawList.from(_:).encode()` already satisfy verbatim and which composes with
the existing emit closure without touching a call site. `CellPresenter` is not
that protocol, and widening it would buy public surface rather than a seam.

The finding also corrected this document: `GamaAppleUI` is excluded as recorded
above, but so are the other two, for a different and stronger reason.

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

Phase 5 is not being done, so nothing resets. Recording one correction this
review produced, because it was wrong in an earlier revision of this document:
**`DrawList/C ABI` is `Locally proven`, not `Hosted proven`**, and `Embedded
core` is locally compile/link proven. Only `WebAssembly/browser` and
`Android/JNI` carry hosted rows among the backends phase 5 would have touched,
and Embed reaches hosted evidence only indirectly through the Android
acceptance that decodes the bytes `gama_embed_v1_frame` emits. Any future
estimate of a refactor's evidence cost must read
[`Capabilities.md`](../../Capabilities.md) rather than assume.

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
5. **Closed without implementation, 2026-09-06.** The spike said one shape
   fit `GamaWASM` and `GamaEmbed`; a closer review of `HostPump.advance`'s
   borrow contract, and of the fact that neither backend ever calls
   `presentDiff()`, said it does not. See *Spike result* above. Reopening
   means designing the wholesale-serialization abstraction, not widening
   `CellPresenter`.

Phase 4 landed as an emitted-line channel rather than a view-tree
declaration: `RenderNode` is an indirect enum every backend switches on
exhaustively, and more fundamentally a chronology is event-shaped while a view
node is re-evaluated every frame, so `SubscriptionContext.emit(_:)` is
exactly-once by construction where a derived one would not be. `App.connect(_:)`
hands an application its channel and closed a real gap: before it, an app
launched through `runAdaptive()` could neither report an outcome nor emit.

Phases 1 through 3 are specified together in
[`2026-09-06-adaptive-terminal-core-design.md`](2026-09-06-adaptive-terminal-core-design.md).
Phases 4 and 5 are specified when reached.
