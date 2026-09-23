# ADR 0018: Viewport events as console notes

Status: Accepted (2026-09-23)

## Context

ADR 0017 logs file, autosave, coordination, and refusal events as console
notes, and it left viewport events out as noise. Donald asked on 2026-09-23
for viewport events as notes too, and chose all four families:
- picking;
- Frame;
- Look through;
- camera moves.

He then asked for the orbit gestures to be covered in the recovered-notice
tests, and for the touch notes to be added to the simulator smoke and
checked by hand on iPad and visionOS.

## Decision

1. **Shared wording in `ViewportSupport`**, so the AppKit viewport
   (`ViewportController`) and the touch viewport (`TouchViewportController`)
   cannot drift. All four notes coalesce, so a repeat of the same event is
   one line.

   | Helper | Note |
   | --- | --- |
   | `notePick` | `picked <name>` or `cleared selection`; nothing when the selection was refused, since the refusal is its own note (ADR 0017) |
   | `noteFrame` | `framed <name>` or `framed the scene` |
   | `noteLookThrough` | `looking through <camera>` |
   | `noteCameraMove` | `moved the camera` |

2. **Only viewport events.**
   - A click or tap in the viewport notes a pick. Selecting from the scene
     panel or the console does not.
   - Orbit, pan, zoom, and pinch each call `noteCameraMove`. A coalesced
     repeat appends nothing, so it does not repaint the host either, and a
     whole drag stays one line without a gesture-end hook.
   - The touch viewport's own setup framing (visionOS) goes through a
     silent `fit()`, so launching logs nothing. Only Frame, through
     `frameSelection()`, is noted.
   - visionOS has no viewport camera. Its Look through selects and frames
     the camera, so it honestly logs `framed Camera`, not "looking through".
3. **Camera moves never touch the recovered notice.** A camera move is not
   a document change, so the status-line notice of ADR 0015 stays. The
   console keeps the recovery note, with the camera note after it.

## Consequences

- **macOS unit tests** (`ViewportNotesTests`, 7) cover:
  - setup logs nothing;
  - picks, including a repeat and a clear;
  - panel and console selections stay silent;
  - Frame, with a subject and with the scene;
  - Look through, ignoring non-cameras;
  - camera moves coalescing across orbit, pan, zoom, and magnify;
  - a real `NSWindow` drag noting one camera move.
- **`UntitledRecoveryTests.orbitGesturesLeaveTheRecoveredNotice`** orbits,
  pans, zooms, pinches, and drags in a real window after a restore. It
  requires the notice to stay, in the model and in the painted status line,
  the console to read `[restored note, "moved the camera"]`, and an edit to
  still clear the notice. Making a camera move clear the notice fails it on
  two lines.
- **Gate:** the plain `--smoke` launch runs `viewportSmokeFailures()` on the
  real touch viewport. It picks the Box, orbits, pinches, frames, and looks
  through the Camera, then requires these notes in order: `picked Box`,
  `moved the camera`, `framed Box`, and `looking through Camera`
  (`framed Camera` on visionOS). The file and recovery launches do not run
  it, so their state is untouched.
- **Verified on the iPad Pro 11-inch (M5) simulator:**
  - the smoke passed;
  - by hand, a viewport tap showed `· picked Sphere`, a drag
    `· moved the camera`, a scene-panel selection nothing, and the
    inspector's Look through `· looking through Camera`.
  - Frame was not tapped by hand, because in iPad portrait the regular
    toolbar runs past the screen edge (`Duplicat…`) and hides it. The smoke
    covers Frame.
- **visionOS was not driven by hand.** The smoke passed on the Apple Vision
  Pro simulator, including `framed Camera` for Look through. But Device
  Hub's background clicks moved the pointer without selecting, and its
  window sat off-screen, out of reach of foreground clicks, so the visionOS
  notes rest on the automated smoke alone.
- **Found, not fixed (since fixed: ADR 0020):** the regular layout's
  toolbar is wider than an iPad in portrait, so Frame and the buttons
  after it are off-screen. This predates this change.
- **Not built:** notes for light and camera inspector changes, which are
  document edits and already visible in the undo label.
