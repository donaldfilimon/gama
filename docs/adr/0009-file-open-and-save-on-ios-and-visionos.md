# ADR 0009: File open and save on iOS and visionOS

Status: Accepted (2026-09-23)

## Context

ADR 0005 added USDA persistence behind a macOS File menu. ADR 0008 brought
the editor to iOS and visionOS, but with no file I/O there. Donald asked
for file open and save on both platforms on 2026-09-23.

These platforms have no menu bar and no open or save panels. Files come
from the system document picker, and a file chosen there can only be read
or written while security-scoped access to it is held.

## Decision

1. **One file core, shared with macOS.** `StudioDocumentSession`
   (GamaStudioEditor, wherever RealityKit compiles) holds:
   - the current file, and the display name ("Untitled.usda" before the
     first save);
   - open, save, and save-to-current-file;
   - export copies, and the saved state.

   It reads and writes inside `startAccessingSecurityScopedResource`, which
   outside a sandbox returns `false` and changes nothing. `StudioAppDelegate`
   now drives the same session, so the macOS File menu and the touch pickers
   cannot disagree about what "saved" means. Its `onStateChange` fires once
   per open (the file is set before the document is replaced) and after
   every edit.
2. **Open edits the file in place.** `UIDocumentPickerViewController(forOpeningContentTypes:asCopy: false)`
   is used for the `.usda` type, so the chosen file becomes the current file
   and a later Save writes back to it.
3. **Save As exports a copy.** The document is written to a temporary
   directory under its display name, then
   `UIDocumentPickerViewController(forExporting:asCopy: true)` copies it
   where the user chooses, and that location becomes the current file.
   `adoptSavedCopy(at:of:)` marks the model saved only if it still holds
   the content that was exported. An edit made while the picker was open
   stays unsaved. The temporary directory is removed when the picker
   finishes or is cancelled.
4. **Save with no file is Save As.** `saveToCurrentFile()` returns `false`
   and writes nothing when there is no file yet; the caller then starts
   Save As.
5. **Unsaved changes prompt before Open.** Open asks Save / Don't Save /
   Cancel, as macOS does. If the user chooses Save and there is no file
   yet, Save As starts and the Open waits: the user taps Open again after
   saving. Chaining a second picker onto the first would present over a
   dismissing controller.
6. **Where the controls are.**
   - `StudioApp` takes an optional `DocumentActions`. When one is supplied,
     Open, Save, and Save As appear first in the regular toolbar, and as a
     first row in the compact one. macOS supplies none, since its File menu
     does this job, so its toolbar is unchanged.
   - A hardware keyboard gets ⌘O, ⌘S, and ⇧⌘S through `keyCommands`.
   - The window scene's title is the file name, with "•" added while there
     are unsaved changes.
7. **The launch smoke covers file I/O.** `--smoke` also writes an export
   copy inside the app's sandbox, reads it back, and requires the same
   document. The gate's `ios and visionos` stage therefore checks
   sandboxed file I/O on both simulators.

## Consequences

- Unit-tested on macOS (`StudioDocumentSessionTests`):
  - Save with no file writes nothing.
  - Save, save in place, and open each behave correctly, with one
    notification per open.
  - Adopting an export copy leaves an edit made meanwhile unsaved.
  - A failed open leaves both the file and the document alone.
  - The file buttons appear only when a host supplies them, and each one
    calls its closure without editing the document.
- Verified by hand on 2026-09-23 in the iPhone 17 simulator:
  - With no file yet, Save opened the export picker and wrote
    `Untitled.usda` to On My iPhone. `usdchecker` reported `Success!`.
  - After adding a box, Save wrote in place with no picker.
  - After adding another box, Open prompted about unsaved changes. Don't
    Save and picking the file reloaded it at revision 0, with the saved box
    and without the unsaved one.
- visionOS shares the code and passes the build and the launch smoke, but
  its picker flow was not driven by hand.
- Not built:
  - opening a `.usda` from Files or another app (declared document types
    and "Open in place" at launch);
  - `UIDocument`-based coordination and autosave;
  - noticing when another app changes the open file.
