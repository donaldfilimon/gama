# Apple backend (GamaAppleUI)

Status: Unverified for the AppKit host. Capability status lives in
[`Capabilities.md`](../Capabilities.md); this guide does not restate
hosted or local proof. iOS/tvOS/visionOS compile proof and VoiceOver
status are in that ledger; no screen-reader acceptance pass is claimed.
Deployment floors: macOS 14, iOS 17, tvOS 17, visionOS 1.

## Embedding

`GamaHostView` is a `@MainActor` NSView/UIView subclass. Install an app:

```swift
let view = GamaHostView(frame: bounds)
view.install(app: MyApp())
```

`install` erases the app behind `@MainActor` closures that own one
noncopyable `FrameHost` (boxed in a private session object). Calling
`install` again replaces the session wholesale and cancels the previous
session's model subscriptions first. Out-of-band state changes request a
frame via the session's non-mutating `invalidate()` path
(`invalidate()` on the view).

## Rendering and input

Frames rasterize through the shared `CellPainter`/`DrawList` pipeline and
draw via CoreGraphics; the most recent `DrawList` is exposed read-only as
`currentDrawList` for accessibility adapters and diagnostics. Keyboard
events translate into `InputEvent` values; the view claims first responder on
window attach.

### Pointer input (ADR 0018)

The view translates pointer input into raw `PointerEvent` samples and never
recognizes a gesture itself: `FrameHost` decides tap, drag, long press,
hover and scroll with the policy of the idiom the view creates it with
(desktop on macOS; vision on visionOS; on UIKit, from
`traitCollection.userInterfaceIdiom`: phone for `.phone`, desktop for
`.mac` (a Catalyst app optimized for Mac), and pad for every other idiom,
including tvOS, an iPad-idiom Catalyst app, and an iPhone or iPad app
running on a Mac, which keeps its original idiom).

- **AppKit.** Left, right and other buttons (`mouseDown`/`Dragged`/`Up` and
  the `rightMouse*` and `otherMouse*` families) become down, move and up
  samples with the button taken from the event type (0 primary, 1 secondary,
  2 middle). A tracking area (`.mouseMoved`, `.inVisibleRect`) turns
  `mouseMoved` into hover, and `mouseExited` into a hover outside the grid,
  never a cancel, so a drag captured outside the view continues. Tablet
  points report as pen. `scrollWheel` accumulates precise (point) deltas by
  the cell size and line deltas one cell per line, carrying the fraction to
  the next event. Modifiers come from `modifierFlags`; timestamps are
  `event.timestamp` in milliseconds.
- **UIKit.** The first touch is tracked by identity through `touchesBegan`,
  `touchesMoved`, `touchesEnded` and `touchesCancelled` (a cancel sample, not
  a release); `UITouch.type` maps a finger to touch, the pencil to pen, and an
  indirect pointer to mouse. Outside tvOS a `UIHoverGestureRecognizer`
  reports hover, and a pan recognizer restricted to indirect scrolling
  (`allowedTouchTypes` empty) reports trackpad and wheel scroll. tvOS keeps
  touch samples only.
- **Scroll sign.** Positive rows reveal the lines below and positive columns
  the columns to the right, on every backend; the platform's delta is negated
  into that sign.
- **Long press.** After every sample the view reads the host's
  `pointerDeadlineMillis` and arms (or cancels) a one-shot timer on the
  main run loop in the common modes (so it fires during event tracking),
  which delivers a stationary sample for the pressed pointer at its
  last cell. The clock is system uptime, the same one `NSEvent.timestamp`
  and `UITouch.timestamp` count in.

`AppleHostPointerTests` drives real `NSEvent`s through a windowed host: a
drag that leaves the pad, the secondary button with modifiers, the armed
deadline and its stationary sample, a second button during a press, the
timer firing in an event-tracking run-loop mode, and the scroll sign. The
UIKit paths are written for iOS, tvOS and visionOS; their compile on those
platforms is not yet measured and no UIKit runtime test drives them.
Italic font styling resolves through `NSFontDescriptor`/`UIFontDescriptor`
symbolic traits.

## Accessibility

VoiceOver reads the frame the host already rendered — there is no second
model of the interface. `AccessibilitySnapshot.from(_:)` (in `GamaDraw`,
platform-free and stdlib-only) replays a `DrawList`'s text commands into a
character grid and reads each row back as one line:

- Later commands paint over earlier ones on the cells they share, exactly
  as the renderer resolves them.
- A style change mid-row does **not** split the row into two
  announcements; the runs rejoin, and the gap between them is preserved as
  spaces.
- Each character advances by `TextLayout.cellWidth(of:)`, so a
  double-width glyph reserves its trailing cell and a zero-width combining
  mark attaches to the glyph on its left instead of consuming a cell.
- `fillRect` commands are ignored: a background color is presentation, and
  announcing it would add noise, not meaning.
- Blank rows are skipped rather than announced as empty, and rows or
  columns outside the grid are clipped away.

`GamaHostView` publishes itself as a container (`isAccessibilityElement`
is false, role `.group`, label "Gama surface") whose children are one
`GamaAccessibilityLineElement` per non-blank row, framed in view
coordinates by the measured cell size and ordered top to bottom.
`view.accessibilitySnapshot` is the public testable seam.

Deriving the snapshot on every frame would charge every host for something
only an assistive-technology client reads, so it is computed lazily,
cached until the next frame replaces it, and the `layoutChanged`
notification is armed only once a client has actually queried the view.
`accessibilityIsObserved` and `accessibilityAnnouncedSnapshot` are
package-visible purely so that contract is testable.

This adapter deliberately carries **no** actions. Focus, activation, and
every other interaction semantic stay in `GamaCore`, where they are
already tested; an accessibility client is told what the frame shows, never
a parallel account of what the application means.

`Examples/AppleHost/main.swift` sketches a minimal AppKit embedding; note
the packaging draft records that it lacks an `NSApplication` run loop and
is not a package target — the runnable proof is the AppKit test suite.

Applications that want Gama to own `NSApplication` and native windows use the
separate `GamaAppleShell` product. See [AppleShell.md](AppleShell.md). The
embeddable `GamaHostView` remains independent and renders only the explicit
primary scene supplied by its app.
