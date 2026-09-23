# Native regions: the node shape and the host contract

Implements the policy in
[ADR 0016](../../adr/0016-native-regions-narrow-own-the-rendering.md) and
settles open question 1 of the
[native view embedding draft](drafts/2026-09-23-native-view-embedding-draft.md).

**Status: implemented on branch `feat/native-regions`; locally gated on
macOS only; no hosted run (billing lock).** The owner approved the design
section by section on 2026-09-23. The implementation plan
(`docs/superpowers/plans/2026-09-23-native-regions.md`) follows this spec
and nothing is claimed in `docs/Capabilities.md` until an implementation has
evidence at the layer that evidence supports (local or hosted).

## The decision: follow the action pattern

A native region is **not** a new `RenderNode` case. `NativeRegion` compiles to
the existing `interactive(id:focusable:child:)` node wrapping its fallback,
stretched with `.frame(maxWidth: .max, maxHeight: .max)` so the region is
flexible on both axes. An `interactive` wrapper only passes through its child's
flexibility, so an unstretched `Text` fallback would size the region to the
text. It
then registers `(NodeID, NativeRegionID)` with the owning host through a new
`BuildContext` hook, the same way `Button` registers its closure through
`registerAction` into the host's `HostActionStore` (cleared by
`beginBuildPass()`, in `Sources/GamaCore/FrameHost.swift`).

Three shapes were considered:

- **A, a new `RenderNode.nativeRegion` case.** This makes regions visible in the
  IR, MLIR output, and any tool reading the tree. It costs a case in
  `flexPriority(along:)`, the deprecated `flexPriority`, every `LayoutEngine`
  pass, `CellPainter`, and the MLIR lowering, plus a new op in the public MLIR
  dialect. The owner confirmed that only a live host needs to know a region
  exists, which removes A's only advantage.
- **B, a `frame` plus a host-side table keyed by `NodeID`.** This collapses
  into C. A `frame` node carries no `NodeID` to key on, so it would need an
  `interactive` wrapper, and at that point it is C.
- **C, the action pattern (chosen).** It needs zero changes to `RenderNode`,
  `LayoutEngine`, `CellPainter`, the MLIR lowering, the TUI, the WASM
  `HTMLSerializer`, the Embed C ABI, or the DrawList wire format. The fallback
  renders on every backend by construction, which is ADR 0016 rule 2. Rule 1
  holds because the region is an ordinary `interactive` node with an identity,
  a laid-out frame, a place in focus order, and hit-testing up to its edge.

What C gives up: a region is invisible to host-less rendering (a
`BuildContext()` with no host, as `gama-demo --emit-mlir` uses). That matches
actions today, and it is correct, because without a host there is nothing to
fill the region. If a future consumer needs regions in the tree, promoting to
a node later is additive. Removing a node after MLIR emits it would not be.

## Data flow

```text
build:   NativeRegion("viewport") { fallback }
           → RenderNode.interactive(id: ctx.id, focusable: f, child: fallback)   (existing IR)
           → context.registerNativeRegion(ctx.id, NativeRegionID("viewport"))    (new hook)
                → the host's region table [NodeID: NativeRegionID], cleared each build pass
layout:  LayoutEngine unchanged → LaidOutNode.collectInteractive → [InteractiveRegion]
publish: FrameHost joins the table with those frames → nativeRegions: [NativeRegionFrame]
present: GamaHostView reads nativeRegions after each advance → places attached views
```

The region table lives in the same host-owned, executor-confined store as the
action tables, and is cleared in the same `beginBuildPass()`. It is never
shared across concurrent hosts, consistent with ADR 0009.

## Public API

### GamaCore (standard library only; the portable-import ban is unchanged)

```swift
/// App-chosen identity for a native region; the same shape as ActionID.
public struct NativeRegionID: Hashable, Sendable {
    public var rawValue: String
    public init(_ rawValue: String)
}

/// Reserves a laid-out region that a presentation host may fill with an
/// application-owned view; every backend paints `fallback` otherwise.
public struct NativeRegion<Fallback: View>: View {
    public init(_ id: NativeRegionID, focusable: Bool = true,
                @ViewBuilder fallback: () -> Fallback)
}

/// One region of a laid-out frame, as a host consumes it.
public struct NativeRegionFrame: Hashable, Sendable {
    public let id: NativeRegionID
    public let node: NodeID      // the interactive node that carries the region
    public let frame: Rect       // absolute cells, from collectInteractive
    public let isFocused: Bool   // whether host focus is on `node` this frame
}
```

- **`BuildContext` gains `registerNativeRegion: (NodeID, NativeRegionID) -> Void`.**
  It is a stored closure and a trailing initializer parameter defaulting to
  `{ _, _ in }`, exactly like `registerNamedAction`, so every existing
  `BuildContext(...)` call still compiles and host-less builds drop regions.
- **`FrameHost` gains `public private(set) var nativeRegions: [NativeRegionFrame]`**
  (visual, depth-first order) and
  **`duplicateNativeRegionIDs: [NativeRegionID]`**. Both are recomputed after
  every build and layout, beside `duplicateIDs`.
- **`HostPump` forwards `nativeRegions`**, the same way it forwards
  `needsFrame` and `wantsQuit`.

`isFocused` is published on each region rather than exposing focus.
`FrameHost`'s `focusedID` is private, and a host only needs one bit per
region. That keeps the focus model where it is.

`focusable` defaults to `true` (owner's choice). A 3D viewport needs keyboard
input, and display-only regions opt out with `focusable: false`, which still
reports the region but leaves it out of focus order.

### GamaAppleUI (`@MainActor`)

```swift
extension GamaHostView {
    public func attach(_ view: GamaPlatformView, to id: NativeRegionID)
    public func detach(_ id: NativeRegionID)
}
```

`GamaPlatformView` is the existing public alias for `NSView` on AppKit and
`UIView` on UIKit, so the method is declared once. (An earlier revision of
this spec said no such alias existed; that was wrong.)

Every new public symbol carries a `///` comment. The doc-coverage gate
requires it, and no allowlist entries are added.

## Host contract

- **Placement runs every frame.** It happens in `GamaHostView` right after
  `session.pump.advance(into:)`, in the same main-actor turn, before the view
  requests display.
  - An attached view whose id is in `nativeRegions` gets
    `frame = pixelRect(region.frame)` and is shown.
  - Every other attached view is hidden, not removed, so its state survives a
    region that is absent for a frame.
  - A region whose frame has zero area counts as absent: its attached view is
    hidden and never takes first responder, so a zero-area view shows nothing
    and focus never lands on an invisible view. The Apple host already
    implements this.
- **No overdraw.** `draw(_:)` skips DrawList commands whose cell rectangle lies
  wholly inside a shown region's frame. A region with no attached view keeps
  its painted fallback, so the Apple host degrades exactly like the cell
  backends.
- **Focus handoff.**
  - When a shown region reports `isFocused` and the previous frame did not,
    the host makes the attached view first responder
    (`window.makeFirstResponder(_:)` on AppKit, `becomeFirstResponder()` on
    UIKit).
  - When `isFocused` turns false, the host takes first responder back.
  - Exactly one view receives first responder per frame, and the host
    reclaims first responder only when it is currently inside a region's view
    that lost focus — never from an unrelated control; `detach` of a focused
    region's view returns first responder to the host.
  - Leaving a native view that consumes Tab itself is out of scope here; it is
    open question 2.
- **Duplicates.** When two regions share an id in one frame, the last
  registration wins and the id appears in `duplicateNativeRegionIDs`. There is
  no trap and no assertion, matching `duplicateIDs`.
- **Lifecycle (ADR 0016 rule 4).**
  - `attach` retains the view only while it is attached, and adds it as a
    subview. These are `GamaHostView`'s first subviews.
  - Attaching a different view to an already attached id detaches the first.
    Attaching to an id not yet laid out is allowed: the view stays hidden until
    its region appears.
  - `detach`, or tearing the host down, removes the subview.
  - Gama never creates, configures, or retains a platform view on its own.
- **Accessibility.** Each shown attached view is inserted as an accessibility
  child, ordered by frame among the per-line elements from
  `GamaHostAccessibility.swift`, so VoiceOver reaches the view's own tree. The
  `AccessibilitySnapshot` still reads the fallback text on every backend.

## Testing

**A new `NativeRegionTests` suite in `GamaTests` (Swift Testing):**
- Registration yields `nativeRegions` with the correct absolute frames and
  visual order.
- A region absent after a rebuild disappears, and a host-less `BuildContext()`
  yields none.
- Duplicate ids are reported, and the last one wins.
- `isFocused` tracks host focus, and `focusable: false` stays out of focus
  order but is still reported.
- The fallback paints identically in the painted `CellBuffer` and its
  `DrawListSerializer` output. Every serializer, including the WASM
  `HTMLSerializer` (internal to its module), consumes that same buffer.
- MLIR emission for a region is exactly the existing `interactive` op around
  the fallback.

**A new `AppleHostNativeRegionTests` suite:**
- An attached view receives `pixelRect(frame)` and is hidden when its region
  goes away.
- Re-attaching replaces the view, and `detach` removes it.
- A focused region makes the attached view first responder.
- Fallback cells under a shown view are not drawn.

**Gates that must stay green:** `check-apple`, `check-apple-platforms` (the
UIKit compile), `check-boundaries` (GamaCore stays standard-library-only),
`check-concurrency-negative`, `check-mlir`, `check-docs`, `check-doc-coverage`,
and `check-package-graph`.

## What this does not decide

These draft questions stay open and are not blocked by this shape:

- 2: Tab traversal out of a native view.
- 3: overlays above a region.
- 4: sub-cell placement.
- 5: publishing regions through the Embed C ABI or the WASM exports. Either
  would be a public-ABI change and needs its own record (ADR 0016 rule 6).
- 7: AppKit and UIKit scope. The API above is declared for both.
  `check-apple-platforms` compiles UIKit, and only macOS gets a runtime test
  here.
