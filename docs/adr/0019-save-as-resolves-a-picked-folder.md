# ADR 0019: Save As resolves a picked folder to the exported file

Status: Accepted (2026-09-23)

## Context

Save As on iOS and visionOS (ADR 0009) writes a temporary copy and hands it
to `UIDocumentPickerViewController(forExporting:asCopy: true)`. The
delegate's URL then becomes the current file (`adoptSavedCopy`), and a
`StudioUIDocument` attaches to it (ADR 0011).

On 2026-09-23 a Save As over an existing `Untitled.usda` in On My iPhone
handed the delegate the folder, `File Provider Storage`, instead of the
file. The `.export` branch adopted the folder and attached to it, and the
attach failed with "isn't in the correct format". Adopting it had already
done the damage. `currentURL` became the folder, so the document was no
longer Untitled. The `onStateChange` that `adoptSavedCopy` sends reached
`keepRecovery()`, which deleted the window's Untitled recovery file
(ADR 0012) before the attach even started.

Measured afterwards on the iPhone 17 simulator (iOS 27.2), logging each
picked URL's `isDirectoryKey`:

| Destination and choice | Document | Delegate received |
| --- | --- | --- |
| Name taken, **Replace** | unsaved changes | the file |
| Name taken, **Keep Both** | unsaved changes | the folder |
| Name taken, **Keep Both** | no changes | the folder |
| Name free (no dialog) | no changes | the file |

So Keep Both is the trigger, and unsaved changes do not matter. In both
Keep Both runs the folder then held a single `Untitled.usda` with the new
bytes. The picker had overwritten the existing file instead of keeping both.
That is the system's behavior, and Gama Studio cannot prevent it.

## Decision

1. **`ExportedFile.resolve(picked:export:notBefore:)`** (platform-neutral,
   `Sources/GamaStudioEditor/ExportedFile.swift`) decides what the picked
   URL means before anything adopts it:
   - A regular file is the answer as it is.
   - A directory (the `isDirectoryKey` resource value, falling back to
     `hasDirectoryPath`, since the picked folder URL has no trailing slash)
     resolves to one file inside it. That file must hold exactly the bytes
     of the temporary export and be modified no earlier than when Save As
     began, less `timestampSlack` (1 s). The file with the export's name is
     preferred. A renamed copy (`Untitled 2.usda`) counts only when it is
     the only match. More than one match is `ambiguous`.
   - Anything else fails: `missing`, `folderWithoutTheCopy`, `ambiguous`.
   Matches are rebuilt under the picked URL rather than taken from the
   directory listing, so the answer stays inside the picker's
   security-scoped URL. The check runs inside
   `StudioDocumentSession.withAccess(to:)`.
2. **The `.export` branch resolves first.** On success it adopts and
   attaches the resolved file. When that differs from what the picker
   returned, it logs the console note `the picker returned the folder
   <name>; saved as <file>` (ADR 0017). On failure it reports "Couldn't save
   …" with the failure's description, and adopts nothing and attaches
   nothing. The pending resume (`afterExport`) is dropped, as a cancelled
   picker drops it. The current file, the saved state, and the Untitled
   recovery file stay as they were.
3. **`Pending.export` records `began`**, taken before the temporary copy is
   written, so a copy that keeps the source's modification date still
   passes.

## Consequences

- Keep Both now saves to the fresh copy, measured in the simulator for both
  Keep Both runs above: the console note appears, then `saved Untitled.usda`.
  The attach to a file inside the picked folder worked under the folder's
  security scope.
- `ExportedFileTests` (12 tests) pins the rules on macOS: a file, a missing
  URL, a folder URL without a trailing slash, the named copy, a lone renamed
  copy, no copy, stale bytes, the timestamp slack, other bytes, two renamed
  copies, another extension, and the failure text. A mutation of each guard
  (modification date, bytes, `isDirectoryKey`, uniqueness) fails a test.
- The gate cannot drive the system picker, so the picker behavior in the
  table above is a manual measurement, not a gate stage.
- **Known residual.** A resolved *file* whose attach then fails still leaves
  `currentURL` pointing at it, with the recovery file already discarded,
  because `adoptSavedCopy` runs before the attach. This ADR does not change
  that order. Fixing it means adopting only after the attach succeeds.
