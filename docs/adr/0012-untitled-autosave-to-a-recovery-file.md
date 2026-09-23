# ADR 0012: Untitled autosave to a recovery file

Status: Accepted (2026-09-23)

## Context

ADR 0011 made iOS and visionOS documents that have a file autosave through
`StudioUIDocument`. An Untitled document had nowhere to autosave, so a crash,
a kill from the app switcher, or the system ending the app lost it. Donald
asked for Untitled autosave on 2026-09-23 and chose a hidden recovery file
over giving every new document a visible file in Files. Untitled stays
Untitled, and nothing appears in Files until the user saves.

## Decision

1. **One invariant.** A recovery file exists only while a window's document
   is Untitled (no current file at all) and has unsaved changes.
   `TouchDocumentController` keeps it:
   - `sessionStateChanged()` creates or updates the file, and removes it
     when the document becomes clean, as when undoing back to where it
     started;
   - `becomeCurrent(_:savingPrevious:)` removes it, because the document has
     a file from then on. That covers both Save As landing and a file opening
     after Don't Save.

   A failed open after Don't Save leaves the Untitled document, and its
   recovery file, in place.
2. **Where.** The file is `Application Support/GamaStudio Recovery/<key>.usda`,
   one per window.
   - The key is the window scene session's `persistentIdentifier`, which the
     system keeps for each window. The plan named `@SceneStorage`. The
     session identifier was chosen instead because SwiftUI may not persist
     scene storage before a foreground kill, and the identifier needs no
     blank first frame while a key is generated.
   - `--recovery-key <k>` overrides the key, and `--smoke` without it uses a
     fresh random key, so a developer's leftover file cannot affect the gate.
   - `UntitledRecovery` accepts only ASCII letters, digits, and `-`, up to 64
     characters, so a key can never name a path.
3. **Writing reuses `StudioUIDocument`.** The first unsaved change creates a
   second, private document at the recovery URL (`.forCreating`, or
   `.forOverwriting` after a restore). Later changes publish the content and
   call `updateChangeCount(.done)`, so UIKit autosaves it on its own
   schedule and when the app enters the background. Its save events are
   ignored, so writing the recovery file never marks the model saved.
   Removing it closes the document without saving and deletes the file in
   the close completion, unless a newer recovery document has started
   meanwhile (an edit right after an undo).
4. **Restoring.** On a window's first appearance, `UntitledRecovery` reads the
   file and calls `StudioDocumentSession.restoreUntitled(_:)`, which calls
   `StudioModel.replaceDocument(_:asSaved: false)`:
   - the content comes back with an empty undo history, as for any open;
   - the saved baseline stays the content the window started from, so the
     document reads as unsaved, gets the Untitled prompt, and keeps
     autosaving to the same file.

   Restoring runs before a file handed over at launch is opened, so that file
   meets the ordinary Untitled prompt. An unreadable recovery file is moved
   aside to `<key>.unreadable-<time>.usda`, never deleted or overwritten, and
   reported.
5. **Gate.** Each simulator runs two launches with a random key:
   - the first makes one change, which must create the file at once, and a
     second, which must arrive through UIKit's autosave; then it exits;
   - the second requires an Untitled document with unsaved changes equal to
     the file, opens a file the way Don't Save leads, and requires the
     recovery file gone.

## Consequences

- **macOS unit tests** (`UntitledRecoveryTests`) cover:
  - key validation;
  - no file, meaning nothing restored;
  - restoring as unsaved Untitled changes with one notification and no undo;
  - a document with a file is never overwritten by a restore;
  - an unreadable file set aside byte for byte, with the document untouched;
  - discarding twice;
  - `replaceDocument(_:asSaved: false)`.
- **Mutation checks, both failing as intended:**
  - without the `discardRecovery()` in `becomeCurrent`, the restore launch
    fails with "opening a file left the recovery file behind";
  - without the recovery `updateChangeCount`, the write launch fails with
    "a later change did not autosave to the recovery file".
- **Verified by hand on 2026-09-23 in the iPhone 17 simulator**, with no key
  argument, so the scene session named the file:
  - after adding a cone, killing the app in the foreground with
    `xcrun simctl terminate` and relaunching brought the cone back at
    revision 0;
  - Open then asked "Save changes to “Untitled.usda”?", so it was restored
    as unsaved.
  - On iPhone the window title, and so its "•", is not visible.
  - Added by ADR 0014: swiping the app away in the app switcher also kept
    the session, and the edit came back.
- **Not verified:**
  - Save As removing the file by hand (the gate covers the same
    `becomeCurrent` path through opening a file);
  - several windows on iPad or visionOS keeping separate files;
  - any of this driven by hand on visionOS, which passes the gate.
- **Not built:**
  - removing recovery files of windows closed for good (orphans) (since
    built: ADR 0013, after a 7-day grace period);
  - a "recovered" message beyond the unsaved state;
  - macOS.
