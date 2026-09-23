# ADR 0010: Opening .usda files from other apps

Status: Accepted (2026-09-23)

## Context

ADR 0009 added file open and save inside the iOS and visionOS app, and
listed opening a `.usda` file from Files or another app as not built. Donald
asked for it on 2026-09-23.

Measured before designing, on 2026-09-23:

- The iOS 27.2 and visionOS 27.2 simulator runtimes already declare `.usda`
  as `com.pixar.universal-scene-description-utf8`, in
  `MobileCoreTypes.bundle`. It conforms to
  `com.pixar.universal-scene-description` and `public.utf8-plain-text`. macOS
  maps the extension the same way, so the app imports no type of its own.
- The app's Info.plist was generated entirely from build settings, and
  document types cannot be set that way.

## Decision

1. **Declare the type and open in place.**
   `Apps/GamaStudioApp/GamaStudioApp/Info.plist` holds only
   `CFBundleDocumentTypes` (role Editor, rank Alternate, the system's `.usda`
   type) and `LSSupportsOpeningDocumentsInPlace = true`. Xcode merges it with
   the generated keys (`INFOPLIST_FILE` beside `GENERATE_INFOPLIST_FILE`).
   The Alternate rank stops the app from claiming to be the default viewer:
   Quick Look stays the default preview for USD.
2. **One route in.** SwiftUI's `onOpenURL` hands the URL to `GamaStudioView`
   as an `IncomingDocument`, which has its own identity so the same file
   handed over twice opens twice. The view passes each request once to
   `StudioHostViewController.openExternalDocument(_:)`. A request that arrives
   at launch, before the view is on screen, waits for `viewDidAppear`,
   because the prompt needs a window to present from.
3. **Same prompt, and the open is never dropped.**
   `TouchDocumentController.openExternally(_:)` asks Save / Don't Save /
   Cancel about unsaved changes, as `open()` does, then opens the file
   through `StudioDocumentSession`, holding security-scoped access, so the
   handed-over file becomes the current file and Save writes back to it.
   ADR 0009 lets an in-app Open wait while Save turns into Save As, because
   the user can tap Open again. A handed-over file cannot be picked again, so
   here the open resumes once the Save As lands. Cancelling that picker, or
   a Save As that fails, drops the open.
4. **`--open <path>`** opens a file at launch through the same
   `IncomingDocument` path. With `--smoke`, the app also checks that:
   - the file became the current file;
   - there are no unsaved changes;
   - the document equals a fresh read of the file.
5. **Gate.** For both simulators, the `ios and visionos` stage now also:
   - checks the built app's Info.plist for the document type and
     open-in-place;
   - copies `Tests/GamaUSDTests/Fixtures/everything.usda` into the app's
     container and launches `--smoke --open` on it.

## Consequences

- Verified by hand on 2026-09-23 in the iPhone 17 simulator, handing
  `Untitled.usda` from the Files app's On My iPhone storage to the app with
  `xcrun simctl openurl`:
  - **Cold launch:** the app started with the saved file (`Box 2`, which the
    sample scene lacks) at revision 0.
  - **Unsaved edit, then Don't Save:** the file was handed over with an
    edit (`Box 3`) open. The unsaved-changes prompt appeared, and Don't Save
    reloaded the file without `Box 3`.
  - **No file yet, then Save:** a fresh app with an edit was handed the
    file. Save opened the export picker; after it wrote, the handed-over file
    opened at revision 0 with an empty undo stack.
- `--smoke --open` with an unreadable file fails, as the negative control
  requires.
- visionOS shares the code and passes the gate's open smoke, but the system
  handing it a file was not driven by hand.
- Not verified: a file shared from another app's share sheet. iOS may give
  the app a copy in its own Inbox instead of the original; Save then writes
  to that copy.
- Not built: `UIDocument` coordination, noticing when another app changes
  the open file, and `.usd`/`.usdc`/`.usdz` (the codec reads only the USDA
  text Gama writes, ADR 0005).
