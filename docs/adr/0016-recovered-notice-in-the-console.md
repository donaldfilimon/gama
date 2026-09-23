# ADR 0016: The recovered notice in the console log

Status: Accepted (2026-09-23)

## Context

ADR 0015 shows a recovered-changes notice in the status line and clears it
at the next document change, so after the first edit nothing records that
the changes were recovered. That ADR listed "the console log does not record
the notice" as not built. Donald asked on 2026-09-23 for the notice to go to
the console log too, and chose a distinct note line over reusing the
command-exchange shape.

## Decision

1. **Notes.** `ConsoleEntry` gains `isNote`, which defaults to `false`, so
   every existing initializer call is unchanged. `ConsoleEntry.note(_:)`
   makes one: no input and never an error. The console panel renders a note
   as `· <message>`, without the `>` prompt or the arrow, so it cannot be
   mistaken for something typed.
2. **One way to post.** `StudioModel.post(notice:)` sets the status-line
   notice and appends the note. Notes and exchanges share the log's
   append-and-trim path (`consoleLogLimit`, 50).
   `UntitledRecovery.restore(into:adopted:)` now calls it.
3. **Lifetimes differ on purpose.** The status-line notice still clears at
   the next document change. The note stays in the console scrollback until
   newer entries push it out.

## Consequences

- **macOS unit tests** cover:
  - the note is logged, painted as `· …`, never as `> …` or `→ …`, and
    outlives the status-line notice;
  - notes and exchanges together keep the 50-entry limit.

  The ADR 0015 clearing test now checks the status-line row itself, because
  the same words stay visible in the console by design. Removing the append
  in `post(notice:)` fails two tests.
- **Gate:** the restore and adopt smokes also require the console note on
  both simulators.
- **Verified on the iPhone 17 simulator:** after a relaunch, the console
  showed "· restored unsaved changes from the last session" above the input
  line, wrapped at iPhone width like the status line.
- **Not built:** other editor events as notes (since built: ADR 0017);
  notes in macOS, which has no recovery.
