# ADR 0011: Autosave and UIDocument coordination on iOS and visionOS

Status: Accepted (2026-09-23)

## Context

ADR 0009 and ADR 0010 let the iOS and visionOS app open and save `.usda`
files, but with plain reads and writes: nothing coordinated with other
processes, nothing saved unless the user tapped Save, and a change made by
another app went unnoticed. Donald asked for autosave and `UIDocument`
coordination on 2026-09-23.

What had to hold:

- **macOS stays as it is.** `StudioDocumentSession` is shared with the macOS
  File menu and pinned by its tests, and `UIDocument` is UIKit-only. macOS
  autosave would need `NSDocument` or a timer, and was not asked for.
- **Swift concurrency.** `UIDocument` is nonisolated, and UIKit calls its
  overrides on its own queues. `StudioModel` is `@MainActor`.
- **Undo.** Undo stays in `EditorSession`, so `UIDocument`'s `undoManager` is
  not used.

## Decision

1. **`StudioUIDocument` sits under the session, on iOS and visionOS only.**
   `TouchDocumentController` holds one for the current file. The session
   stays the authority on content and saved state:
   - an open adopts what the document read (`adoptOpened(_:from:)`);
   - a save that landed marks it saved (`adoptSavedCopy`), but only when the
     content still matches.

   The document never touches the model. Content crosses as `SceneDocument`
   values behind a `Mutex`:
   - the model's latest content, published on every change;
   - what the last open or revert parsed;
   - the save in flight;
   - the last error, as a string.

   Its events name it by `ObjectIdentifier` and run on the main actor.
2. **A document autosaves once it has a file.** On every model change the
   controller publishes the content and calls `updateChangeCount`: `.done`
   when it differs from the saved content, and `.cleared` when it does not,
   so undoing back to the saved content cancels a pending autosave. UIKit
   then autosaves in place, the Files-app convention.
   - An Untitled document has no file and does not autosave. Its Save runs
     Save As, and the Save / Don't Save / Cancel prompt remains for it only.
   - With a file, Open and a handed-over file save pending changes first,
     without asking, then switch.
   - Save saves now instead of waiting for autosave.
   - Save As exports a copy as before, then holds that copy as the new
     current file without reading it back, so an edit made while the picker
     was open survives and autosaves there. The previous file is closed
     without saving: it keeps what it last saved.
3. **Changes from other apps.** `presentedItemDidChange` does not call
   super, which would let UIKit revert on its own. It reads the file with a
   coordinated read, as the file's own presenter, and reports a change only
   when the content differs from what this document last read or wrote.
   This check is necessary: UIKit also calls it for the document's own
   autosave (measured, 12 ms after the edit). The controller then:
   - reloads the file when nothing is unsaved (not undoable, like an open);
   - otherwise asks: **Revert** loads the file; **Keep Mine** marks the
     document changed, so the next save overwrites the file.
4. **UIKit's other signals.**
   - `UIDocument.stateChangedNotification` with `.savingError` shows one
     alert per failure.
   - On iOS 26 and visionOS 26, `didMoveToWritableLocationNotification`
     updates the session's current file (`fileMoved(to:)`).
   - Security-scoped access is held for the document's lifetime.
5. **Gate.** The `--smoke --open` launch (ADR 0010) now also checks the
   whole cycle on both simulators:
   - the file opens as a coordinated document in the `.normal` state;
   - an edit schedules autosave, and `autosave` writes it, after which the
     document reads as saved;
   - another writer's coordinated write reloads it;
   - the same write with unsaved changes asks, and Keep Mine leaves the
     document to overwrite the file.

## Consequences

- **The Swift 6.4 compiler did not see the `@unchecked Sendable`
  conformance on the `UIDocument` subclass consistently.** Per-file
  compiles saw it only in some files, and which files flipped with where a
  probe was placed. Nothing in the design depends on the document being
  `Sendable`: events carry identifiers, and state sits in a `Sendable`
  class around the `Mutex`.
- **The smoke's stand-in for another app writes off the main actor.** A
  coordinated write on the main thread deadlocked with the document
  relinquishing the file through the main queue. A real other app is
  another process and does not have this problem.
- **Mutation check:** removing the `updateChangeCount` call fails the smoke
  on four lines, starting with "an edit did not mark the document for
  autosave".
- **Verified by hand on 2026-09-23 in the iPhone 17 simulator:**
  - An in-place file chosen with Open (`File Provider Storage/Untitled.usda`)
    autosaved an added sphere about 8 s after the edit, with no Save tap.
    UIKit's log shows the autosave completing on that URL.
  - A handed-over copy (`Documents/Inbox`) autosaved about 4 s after an edit.
  - Opening a file while the current one had no unsaved changes switched
    with no prompt.
- **Not verified:**
  - a change made by another process: the smoke's writer is a second
    `NSFileCoordinator` in the same process;
  - a real `.savingError`;
  - the writable-location move;
  - any of this driven by hand on visionOS, which shares the code and
    passes the gate's smoke.
- **Not built:**
  - autosave for Untitled documents (a recovery location and restoring it
    at launch);
  - iCloud version conflicts (`.inConflict`);
  - macOS autosave.
