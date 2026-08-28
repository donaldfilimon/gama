# Apple backend (GamaAppleUI)

Status: AppKit host locally runtime proven (instantiation, layout,
invalidation, draw-list production) and hosted proven on the macOS job;
iOS/tvOS/visionOS are compile proven only (simulator builds — no hosted
runtime execution). VoiceOver accessibility from the draw list is
implemented and locally proven on AppKit; UIKit shares the derivation but
is compile proven only, and no screen-reader acceptance pass is claimed.
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
`currentDrawList` for accessibility adapters and diagnostics. Keyboard,
pointer, scroll, and (on touch platforms) touch events translate into
`InputEvent` values; the view claims first responder on window attach.
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
