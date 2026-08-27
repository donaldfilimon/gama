# Apple backend (GamaAppleUI)

Status: AppKit host locally runtime proven (instantiation, layout,
invalidation, draw-list production) and hosted proven on the macOS job;
iOS/tvOS/visionOS are compile proven only (simulator builds — no hosted
runtime execution). VoiceOver accessibility from the draw list is a
ledgered Slice C item (Provisional). Deployment floors: macOS 14, iOS 17,
tvOS 17, visionOS 1.

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
(`requestFrame()` on the view).

## Rendering and input

Frames rasterize through the shared `CellPainter`/`DrawList` pipeline and
draw via CoreGraphics; the most recent `DrawList` is exposed read-only as
`currentDrawList` for accessibility adapters and diagnostics. Keyboard,
pointer, scroll, and (on touch platforms) touch events translate into
`InputEvent` values; the view claims first responder on window attach.
Italic font styling resolves through `NSFontDescriptor`/`UIFontDescriptor`
symbolic traits.

`Examples/AppleHost/main.swift` sketches a minimal AppKit embedding; note
the packaging draft records that it lacks an `NSApplication` run loop and
is not a package target — the runnable proof is the AppKit test suite.
