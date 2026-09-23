# ADR 0015: A notice for recovered changes

Status: Accepted (2026-09-23)

## Context

ADR 0012 restores a window's unsaved Untitled changes at launch. ADR 0014
lets a window adopt a closed window's changes. In both cases the only sign
was the unsaved state, and ADR 0014 listed "telling the user the changes came
from another window" as not built. Donald asked for a "recovered" message on
2026-09-23. He chose a status-line notice, shown for both adoption and a
window restoring its own changes, over a modal alert.

## Decision

1. **`StudioModel.notice`** is editor state: an optional one-time message.
   The status line shows it last:
   `rev N · <selection> · undo: <label> · <refusal> · <notice>`.
2. **Cleared by the next document change.** It is cleared in the edit
   funnel (edits, undo, redo) and in `replaceDocument` (opening), before
   `onDocumentChange` runs. Selecting is not a document change and leaves
   it.
3. **Set by `UntitledRecovery.restore(into:adopted:)`**, the one place both
   paths share, and only when something was restored into a document still
   Untitled:
   - `restoredNotice`: "restored unsaved changes from the last session";
   - `adoptedNotice`: "recovered unsaved changes from a closed window".

   The host passes `adopted` from the adoption it just made.

## Consequences

- **macOS unit tests** cover:
  - both texts, in the model and in the painted status line;
  - the notice survives a selection change and clears on an edit, an undo,
    and an open;
  - a document with a file gets no notice.

  Removing the line that sets the notice fails two of them.
- **Gate:** the restore and adopt smokes now also require the matching
  notice on both simulators.
- **Verified by hand on the iPhone 17 simulator:** relaunching restored the
  window's own file and showed "restored unsaved changes from the last
  session"; adding a box cleared it. At iPhone width the notice wraps the
  status line onto a second line until it clears.
- **Not built:** the console log does not record the notice; macOS has no
  recovery, so no notice there.
