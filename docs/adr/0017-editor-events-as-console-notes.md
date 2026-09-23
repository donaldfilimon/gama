# ADR 0017: Editor events as console notes

Status: Accepted (2026-09-23)

## Context

ADR 0016 added console notes (`· <message>`) for recovered changes only.
Donald asked on 2026-09-23 for other editor events to be logged as notes too.
He chose all four families:
- file events;
- coordination events;
- refusals from buttons;
- autosave, accepting that autosave is frequent.

The status-line notice stays reserved for recovery (ADR 0015). These are
notes only.

## Decision

1. **`StudioModel.log(note:isError:coalescing:)`** appends a note through
   the log's shared append-and-trim path. `isError` renders dim, as a typed
   refusal does. With `coalescing`, a note equal to the last entry is not
   repeated, so a run of `autosaved <file>` stays one line; any entry in
   between breaks the run. `post(notice:)` logs through it.
2. **Refusals from buttons.** `attempt`, where every refused edit, undo,
   redo, and selection lands, logs `refused: <error>` (dim). It does not
   while `runConsole` is running a line (a `consoleDepth` counter), because
   that line's exchange already shows the refusal.
3. **File events, the same wording on both hosts.**

   | Event | macOS | iOS/visionOS |
   | --- | --- | --- |
   | `opened <name>` | `StudioAppDelegate.open(_:)` | `finishOpening`, when opening |
   | `saved <name>` | `save(to:)`, used by Save and Save As | an explicit save (the `explicitSavePending` flag, cleared if that save fails), or Save As landing |
   | `autosaved <name>` (coalescing) | none | any other save of the current file |
   | `couldn't <action>: <reason>` (dim) | open and save failures, which are then rethrown; the alerts are unchanged | beside every alert `report` shows |

   The recovery file's own autosaves stay silent. They are internal, and
   their events were already ignored.
4. **Coordination (iOS/visionOS).**
   - `reloaded <name>: changed by another app`;
   - `kept your version of <name>; it replaces the file at the next save`;
   - `<name> moved to a writable location`.
5. **Notes repaint the host.** A note can arrive outside any gama action,
   for example a UIKit picker callback or an AppKit panel. `StudioModel`
   gained `onConsoleChange`, and both hosts repaint from it, deferred to the
   next main-actor turn as ADR 0008 requires. The macOS delegate coalesces
   its deferred repaints to one per turn, so an open and its note still
   repaint once.

## Consequences

- **The repaint came from verifying by hand.** On the iPhone simulator, a
  failed open's error note was logged but not shown until something else
  repainted. `aNoteFromOutsideTheHostRepaintsIt` now pins it on macOS, and
  after the fix the touch app showed "· saved Untitled.usda" live.
- **macOS unit tests** (`ConsoleNotesTests`) cover:
  - coalescing: runs, gaps, and uncoalesced repeats;
  - error notes;
  - a refused Undo and a refused selection each logged once;
  - a typed `undo` logged only as its exchange;
  - notes painted without the prompt;
  - File-menu open, save, and failure notes;
  - the repaint.

  The earlier test that pins one repaint per File-menu open still passes
  with the coalescing.
- **Mutation checks, each failing as intended:**
  - without the refusal log, two tests fail;
  - without the console-depth guard, the no-double-refusal test fails;
  - without the autosave note, the simulator file smoke fails with `no
    console note "autosaved gate-open.usda"`.
- **Gate:** the `--smoke --open` file smoke on both simulators requires, in
  order:
  - `opened`;
  - `autosaved`;
  - `reloaded … changed by another app`;
  - the kept-your-version note.
- **Verified by hand on the iPhone 17 simulator:** Save As with Replace
  logged "saved Untitled.usda".
- **Found, not fixed here:** one earlier Save As received the folder URL
  ("File Provider Storage") from the export picker instead of the file.
  The app then tried to open the folder, and the Untitled recovery was
  discarded. A repeat returned the file correctly. This predates this
  change (ADR 0009/0011) and is flagged as its own task.
- **Not built:**
  - viewport events (selection, Frame, Look through) as notes, which were
    left out as noise (since built: ADR 0018);
  - macOS autosave notes (macOS has no autosave).
