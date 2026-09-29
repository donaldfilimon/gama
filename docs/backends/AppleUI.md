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

## Native presentation host (macOS)

`GamaNativeHostView` (ADR 0017, design in
[`2026-09-23-native-presentation-design.md`](../superpowers/specs/2026-09-23-native-presentation-design.md))
is a second AppKit host, separate from `GamaHostView`. It presents the same
surface with real AppKit controls instead of a painted grid:

| Presented kind | AppKit view |
| --- | --- |
| label | non-editable, non-bezeled `NSTextField` |
| separator | `NSBox` of type `.separator` |
| background, border | layer-backed view (fill; border width, color, corner, title) |
| button with a plain-text label | `NSButton`, push style |
| button with a composite label | clickable container presenting the label's views |
| toggle | `NSButton`, checkbox style |
| text field | editable `NSTextField` with placeholder |
| progress | `NSProgressIndicator` (bar; spinner when indeterminate) |
| native region | the attached application view, or the fallback presented natively |
| other interactive node | focusable container forwarding keys to `FrameHost` |

```swift
let view = GamaNativeHostView(frame: bounds)
try view.install(app: MyApp())
```

Layout stays Gama's. The host lays out in points with
`AppKitLayoutMetrics`: system-font text measured by AppKit and cached,
control sizes from prototype controls, and one authored cell converted to
the rounded size of `"M"` in the system font. Each frame is reduced to a
`PresentedNode` tree and the `PresentationDiff` between frames is applied to
subviews, so a control keeps its identity (and a text field its editor)
across frames. Buttons and checkboxes call `FrameHost.activate(_:)`, text
edits go through `FrameHost.setText(_:_:)` (which rebinds per-surface
`@Reactive` state first, like any action), first-responder changes report back through
`FrameHost.focus(_:)`, and `nextKeyView` follows Gama's focus order. Text
with no explicit color uses `labelColor`, so light and dark appearance
follow the system; the cell-only focus highlight is not drawn, including the
wrapper a focused button puts around a composite label. After every frame
the host writes each text field's and checkbox's value from the new
descriptor into the AppKit control, so a binding that clamps or refuses an
edit puts the control back in line with the model.

`GamaShell.run(_:presentation: .native)` opens every window with this host,
sized in points. `gama-apple-demo --native` opens the demo that way, and
`gama-apple-demo --native-smoke` hosts it offscreen and exits 0 only when a
push button, checkbox, text field, progress indicator, and label are
presented as AppKit views.

Known limits: a progress view's label is its accessibility label only, not
drawn; there is no UIKit native host; layout cost with
`AppKitLayoutMetrics` against `.cell` metrics has not been measured
(`docs/Performance.md` has no entry for it); no row in
[`Capabilities.md`](../Capabilities.md) covers this host yet.
