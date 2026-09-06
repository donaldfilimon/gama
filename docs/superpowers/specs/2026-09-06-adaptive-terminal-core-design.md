# Adaptive terminal surface: core, presenter, and selection (phases 1-3)

Status: Implemented and locally verified 2026-09-06. Twenty Swift Testing
cases across three suites pass, and the suite is 291 in 53 suites. Local gates
are not hosted proof; the six-job matrix has not run against this work. One
naming deviation from the design as written is recorded in *Phase 2*.
Specifies phases 1 through 3 of
[`2026-09-06-adaptive-terminal-surface-design.md`](2026-09-06-adaptive-terminal-surface-design.md),
which holds the agreed decisions, non-goals, and evidence cost. At the close of
phase 3 an unmodified Gama application renders a live TUI on a terminal and
plain pipeable output when redirected, and reports a process exit code.

## Phase 1 — `CompletionStatus` in `GamaCore`

A retained UI is state over time; a process is an event with an outcome. The
core has no concept of "finished", so a backend cannot know when to stop or
what to exit with. Quiescence was considered and rejected: it can only ever
produce exit code `0`, so failure becomes unreportable.

```swift
/// The terminal outcome an application reports when its work is done.
public struct CompletionStatus: Hashable, Sendable {
    public var code: Int32
    public var message: String?

    public static let success: CompletionStatus
    public static func failure(code: Int32, _ message: String? = nil) -> CompletionStatus
}

extension SubscriptionContext {
    /// Record that the application has finished, with the outcome to report.
    public func complete(_ status: CompletionStatus)
}
```

`FrameHost` gains `completion: CompletionStatus?`, set once and thereafter
immutable; a second `complete` call is ignored rather than overwriting, so a
late success cannot mask an earlier failure. The host sets its dirty flag on
completion so the backend observes it through the existing frame path and no
new notification mechanism is introduced.

`Int32` and `String` are stdlib types, so `check-boundaries.sh` continues to
pass unchanged. `FrameHost` remains `~Copyable`; `completion` is read through
the same borrow discipline as `needsFrame`, which means tests must bind it to a
local before `#expect` (see [Testing](#testing)).

Completion is presentation-agnostic. A TTY run and a piped run agree on *when*
the application is finished and differ only in how they show it.

## Phase 2 — `StreamPresenter` and the `Presenter` protocol in `GamaDraw`

`GamaDraw` already turns a laid-out tree into cells and cells into either a
differential ANSI stream or a `DrawList`. It also already derives linear text
from a `DrawList` for accessibility (`AccessibilitySnapshot`), which is the same
problem as presenting to a consumer that cannot see a grid.

Phase 2 adds a third derivation and names the shared abstraction.

The design named this protocol `Presenter`. **It shipped as `CellPresenter`**,
because naming it `Presenter` would have claimed a generality that had not been
established when it was written: at that point the spike had not run, and a
protocol over `CellBuffer` is not a protocol over every backend. The spike has
since shown the `CellBuffer` family is exactly `GamaTUI`, `GamaWASM`, and
`GamaEmbed`, so the narrower name is the accurate one and is kept.

```swift
/// Reconciles a CellBuffer's pending frame into text for one consumer,
/// then swaps the buffers.
public protocol CellPresenter {
    associatedtype Output
    mutating func present(_ buffer: inout CellBuffer) -> Output
}

public struct AnsiPresenter: CellPresenter { /* -> String, wraps presentDiff */ }
public struct StreamPresenter: CellPresenter { /* -> [String] */ }
```

`CellBuffer` gained two public queries the line presenter needs and the ANSI
one did not: `rowChanged(_:)`, the per-cell comparison `presentDiff()` already
makes raised to a whole row, and `rowText(_:)`, which skips double-width
continuation cells and trims trailing blanks.

The protocol is introduced **additively**: `CellBuffer`'s ANSI path conforms to
it, and no existing call site changes. Converting the other backends is phase 5
and is gated on a spike, for the reasons in the umbrella's *Risk* section.

`StreamPresenter` derives lines by diffing successive frames, reusing the
comparison that already drives `presentDiff()`, and emitting only rows whose
content changed. Repeating a full snapshot per frame was considered and
rejected: it is correct but produces a block per frame rather than a
chronology, which is not what a log consumer wants.

Two properties matter and are pinned by tests:

- **Chronological, not positional.** Output is append-only. A row that changes
  produces one line; a row that does not produce nothing.
- **Semantically lossy, and honestly so.** Content that never reaches the cell
  grid cannot appear in the stream. Phase 4's opt-in `StreamOutput` exists
  precisely because derivation cannot invent what was never drawn, and the
  documentation must say so rather than implying parity.

This module imports no platform module, so the whole derivation is testable
with no terminal, no file descriptor, and no I/O.

## Phase 3 — Detection and selection in `GamaTUI`

`GamaTUI` owns the terminal today: termios, the Windows Console VT path, the
C-only signal target, and `STDOUT_FILENO` (`Sources/GamaTUI/Terminal.swift:100`).
It does not currently ask whether that descriptor is a terminal.

Phase 3 adds the question and the branch:

- On startup, test `isatty(STDOUT_FILENO)`.
- A TTY selects the existing ANSI presenter and the existing input loop. This
  path must be byte-identical to today's behavior; that is a test obligation,
  not an assumption.
- A non-TTY selects `StreamPresenter`, installs no termios state, registers no
  signal dispositions, and reads no input.
- When `FrameHost.completion` is set, the run ends and the process exits with
  `status.code`, writing `status.message` to stderr when present.

Explicit override is supported so the detection can never be the only path:
`--gama-plain` forces the stream presenter and `--gama-tui` forces the
interactive one. Honoring `NO_COLOR` is deliberately **not** part of this phase;
color suppression is a separate concern from presenter selection and conflating
them would make one flag mean two things.

No termios state on the non-TTY path is the reason this is safe in CI: there is
no terminal to corrupt and no disposition to restore, so the rescue machinery in
`TerminalRescue.swift` is not engaged at all.

## Defect found after the phases landed

Unit tests drove `StreamRenderer` directly and all passed while the shipped
entry point hung. An out-of-repo probe calling `App.runAdaptive()` through a
real pipe found it: a surface with no input source can never be sent a quit
key, so a loop that ended only on quit-or-completion spun forever for an
application that never declared a status. It rendered one frame and then
burned CPU indefinitely.

The fix adds `Renderer.waitsForInput`, defaulted `true` so no existing
backend changes, and `false` on `StreamRenderer`. The loop now treats a
clean iteration on an input-less backend as the end of the run. A declared
completion is still checked first, so this never launders a failure into a
silent success. The consequence to know: an application doing asynchronous
work on an input-less surface must declare completion rather than rely on
becoming dirty later, because the run ends at the first quiescent frame.

The lesson is the one the repository already encodes about gates: driving a
component directly is not evidence about the entry point that composes it.

## Testing

Swift Testing only, in the single `GamaTests` target, per ADR 0003.

| Phase | Coverage |
| --- | --- |
| 1 | `complete` records once; a second call does not overwrite; completion raises the dirty flag; a host with no completion reports `nil` |
| 2 | Derivation is chronological; unchanged rows emit nothing; content absent from the grid is absent from the stream; the ANSI path's output is unchanged by conforming it to `Presenter` |
| 3 | Presenter selection follows the descriptor; overrides beat detection; the non-TTY path installs no termios state; exit code equals `status.code` |

Phase 2 needs no I/O at all. Phase 3's selection logic is separable from the
descriptor by injecting the TTY answer rather than calling `isatty` inline,
which keeps the branch testable without allocating a pty.

`#expect` cannot read a bare property off a `~Copyable` host: the macro expands
to `__checkPropertyAccess`, which requires `Copyable`, and the diagnostic names
that helper rather than the property. Bind `completion` to a local first, as
every `needsFrame` assertion in `GamaTests` already does.

Two obligations are easy to miss. Every new public declaration needs a `///`
comment or `check-doc-coverage.sh` fails, and an allowlist entry is not an
acceptable substitute. Phase 3 changes a hosted-proven backend's entry path, so
the TTY branch needs an explicit no-change proof rather than an inference from
a green suite.

## Verification

Phases 1 and 2 are exercised by `check-apple.sh`, `check-boundaries.sh`,
`check-docs.sh`, and `check-doc-coverage.sh`. Phase 3 additionally touches the
Linux and Embedded gates, since `GamaTUI` builds there. No new gate is added and
`scripts/check.sh` keeps its thirteen entries; the array remains the authority.

Local gates are not proof of the platform matrix. Integration requires the full
six-job hosted acceptance run at the merge commit, per
[`Capabilities.md`](../../Capabilities.md). Phases 1 through 3 add surface
without altering existing backend behavior, so no ledger row resets — but the
byte-identical TTY claim in phase 3 is exactly the kind of assertion that needs
hosted evidence rather than a local green.

## Open questions

- The concrete shape of `Presenter` is deliberately unfixed here. Phase 2 only
  requires that the ANSI path conform without changing behavior; the shape that
  also spans AppleUI, WASM, and Embed is phase 5's spike.
- Whether `complete` should end a TTY run as well, or only stop the work while
  leaving the window up for the user to dismiss. Decision 4 in the umbrella says
  completion means completion on both paths; the interaction with an
  auxiliary-scene macOS shell that outlives one host is unexamined.
