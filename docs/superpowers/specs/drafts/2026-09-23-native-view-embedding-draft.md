# Native view embedding — draft

Status: Draft. Open questions, not a commitment. Nothing here is built.

## Why this is written down

The first consumer is a 3D authoring app, Gama Studio (a separate repository),
whose editor panels are meant to be Gama views with a RealityKit viewport in
the middle of the Apple window. Gama cannot express that today: no view can
reserve a laid-out region and let a platform view fill it.

The ask is narrow on purpose. It is **a reserved region with a portable
fallback**, not a wrapped widget. Gama would still lay the region out, route
focus to it, and paint something portable in it. Only the pixels inside the
region on a backend that opts in would come from a view the application owns.

### A naming collision to clear first

"Surface" already means a presentation host in this repository (ADR 0011,
"reactive state is per-surface"; `SurfaceMode`; `EnvironmentValues.surfaceSize`),
and "slot" means a plugin contribution point (`PluginSlot`). This draft uses
**native region**: `NativeRegion` for the view, `NativeRegionID` for its
identity. Please don't reuse either existing word for this.

## What exists, stated precisely

- **The IR has no opaque node.** `RenderNode` (`Sources/GamaCore/RenderNode.swift`)
  has fifteen cases: `empty`, `text`, `stack`, `overlay`, `group`, `spacer`,
  `divider`, `padding`, `border`, `background`, `frame`, `flexFrame`, `styled`,
  and `interactive`. Only `interactive(id:focusable:child:)` carries an
  identity, and nothing is a placeholder for content Gama doesn't draw.
- **A new case touches every exhaustive switch.** These are `flexPriority(along:)`
  (whose comment says it is exhaustive so a new case must choose its flex
  behavior), `LayoutEngine`'s measure, layout and flex-minimum passes, the
  `CellPainter` switch (no `default`), and the MLIR lowering in
  `Sources/GamaMLIR/Lowering.swift` (one op per case, no `default`). The TUI,
  WASM (`HTMLSerializer`) and Embed backends consume only the painted cell
  grid, so they don't switch on `RenderNode` and would show whatever the
  painter writes.
- **Identity doesn't survive into the DrawList.** `DrawList.from(_:)` is built
  from the painted `CellBuffer` and has two commands, `fillRect` and `text`.
  The v1 wire format (ADR 0005) decodes strictly, with `version == 1` and no
  skip-length on commands. An old decoder can't pass over a new command, so
  carrying a region in the DrawList would mean a version bump.
- **The Apple host sees cells, not layout.** `GamaHostView` replays
  `currentDrawList` in `draw(_:)`, has **no subviews**, and maps cells to points
  with `pixelRect(_:)`: `x·cellWidth, y·cellHeight` from a monospaced 14 pt
  cell. The seam already exists: `HostPump.advance()` returns
  `AdvancedFrame.frame`, the `LaidOutNode` tree with absolute cell frames.
  Only the `advance(into:emit:)` path the view uses discards it.
- **Hit-testing and focus live in `FrameHost`.** Interactive regions are
  collected by `LaidOutNode.collectInteractive(into:)`. Duplicates are reported
  in `FrameHost.duplicateIDs`, and the topmost region containing the pointer
  wins. Tab, Shift-Tab and spatial arrow focus are all owned by `FrameHost`.
- **Accessibility reads text only.** `AccessibilitySnapshot` replays `.text`
  commands into lines, and `GamaHostAccessibility.swift` exposes one element
  per non-blank line.

## The ADR 0001 tension, argued rather than waved away

ADR 0001 decided that Gama owns rendering end to end, that backends "only
translate events in and present frames out", and that "visual and interaction
semantics cannot fork per platform". The native-desktop-backends draft reads
it as "Gama does not wrap platform widgets". Taken literally, a native view
inside a Gama window breaks all three.

The proposal below is meant to keep the part of 0001 that matters and give up
only what it has to:

- **What stays in the shared IR and behaves identically on every backend:**
  layout (the region is a node with a size and a frame), focus order (the
  region takes part in Tab traversal through `interactive`), pointer
  hit-testing up to the region's boundary, and a painted **fallback** that
  every cell backend shows. A TUI, a browser or an embedder sees a region that
  is laid out, focusable and labeled, with the same semantics as the Apple
  host.
- **What gives way, only on backends that opt in, and only inside the region:**
  the pixels, and the events delivered inside it. That content belongs to the
  application and is explicitly **outside** Gama's guarantees, the same
  boundary shape as the `gama_embed_v1_*` C ABI: one explicit escape hatch at
  the edge, not a general widget-wrapping layer.

That is still an amendment. If this is accepted, it needs its own ADR (0016)
that narrows 0001's consequence. Written that way, it's a documented
exception. Slipped in as a helper, it would be a silent one.

## The proposal

### IR

- **A new case, `RenderNode.nativeRegion(id: NativeRegionID, fallback: RenderNode)`.**
  - It is built by a view:
    `NativeRegion(_ id: NativeRegionID) { fallback }`.
  - `NativeRegionID` is an app-chosen value wrapping a string, the same shape
    as `ActionID`. It is plain standard-library data, so GamaCore stays inside
    the portable-import ban.
- **Layout.** The region measures like its fallback and is flexible on both
  axes, so its size normally comes from an enclosing `.frame` or flex
  container. Its `flexPriority` is `.flexible(weight: 1)`, which is a decision
  the exhaustive switch forces anyone adding the case to make.
- **Painting.** `CellPainter` paints the fallback. With no backend change,
  TUI, WASM and Embed show the fallback, such as a bordered "3D viewport"
  label.
- **MLIR.** The lowering gains a `gama.native_region` op carrying the id and
  the lowered fallback.

### Identity channel beside the frame, not inside the DrawList

- `LaidOutNode` gains `collectNativeRegions(into: inout [NativeRegionFrame])`,
  mirroring `collectInteractive`. `NativeRegionFrame` is an `id` plus an
  absolute cell `Rect`.
- `FrameHost` exposes the current frame's `nativeRegions`, and reports
  duplicate region ids the way `duplicateIDs` reports duplicate node ids.
- **The DrawList and its wire format don't change.** Regions travel next to
  the frame to hosts that ask for them, and version 1 stays the only version.

### Apple host

- **The API.** `GamaHostView.attach(_ view: NSView, to id: NativeRegionID)`,
  `detach(_ id:)`, and the `UIView` equivalents.
- **Ownership.** The application owns the view. The host holds it only while
  it is attached and adds it as a subview; these would be `GamaHostView`'s
  first subviews.
- **Per frame.** After each frame the host reads `nativeRegions` (through a
  `HostPump` path that keeps the `LaidOutNode`). It sets each attached view's
  frame to `pixelRect(region.frame)`, and hides any attached view whose region
  is absent from the frame. A region with no attached view shows its painted
  fallback, so the Apple host degrades exactly like the cell backends.
- **Drawing.** The host doesn't draw the fallback's cells under an attached
  view. That avoids overdraw and makes the boundary easy to see during
  bring-up.

### Input and focus (baseline)

- **Pointer.** AppKit and UIKit hit-testing deliver pointer events inside an
  attached view to that view. `FrameHost` never sees them.
- **Focus.** The region is wrapped in `interactive(id:focusable: true)`, so it
  joins Gama's Tab order. When Gama focus lands on it, the host makes the
  attached view first responder. When the attached view resigns, focus
  returns to the host view.
- **Known gap.** Getting Tab to leave a native view that consumes Tab needs
  key interception. That is open question 2.

### Accessibility

- `AccessibilitySnapshot` keeps reading the fallback's text, so every backend
  has a label for the region.
- The Apple host inserts each attached view as an accessibility child at its
  frame, between the line elements above and below it, so VoiceOver reaches
  the view's own accessibility tree.

## Costs and known limits

- **Frames snap to the cell grid.** Region edges land on multiples of the
  cell size. That's fine for a viewport panel and coarse for anything
  pixel-aligned.
- **Z-order.** An attached view sits above all of Gama's drawing, so a Gama
  overlay, popover or menu can't cover it.
- **Tab traversal out of the view** is incomplete without key interception.
- **Embed and WASM** publish no regions in this proposal. Their embedders see
  the fallback only.
- **Every exhaustive `RenderNode` switch gains a case,** including MLIR. That
  cost is deliberate and small.

## What the work would be, and how it would be proven

A single vertical slice, after acceptance and ADR 0016:

1. **GamaCore.** `NativeRegionID`, the `nativeRegion` case with its layout and
   flex behavior, `NativeRegion`, `collectNativeRegions`, and
   `FrameHost.nativeRegions` with duplicate reporting. Every public symbol gets
   documented, because the doc-coverage gate requires it.
2. **GamaDraw and GamaMLIR.** The painter case (fallback) and the lowering op.
3. **GamaAppleUI.** `attach`/`detach`, per-frame placement, first-responder
   handoff, and the accessibility child.
4. **Tests.**
   - `GamaTests` suites: region collection and absolute frames, duplicate
     reporting, fallback painted identically by TUI/HTML/DrawList
     serialization, MLIR emission.
   - An `AppleHostNativeRegionTests` suite: an attached view gets
     `pixelRect(region.frame)`, is hidden when its region disappears, and gets
     first responder on Gama focus.
5. **Gates that must stay green.** `check-apple`, `check-apple-platforms`,
   `check-boundaries` (the portable-import ban and the libm symbol scan),
   `check-mlir`, `check-docs`, and `check-doc-coverage`.
   `docs/Capabilities.md` gains a row only when there is evidence for it, at
   the layer that evidence supports.

## Open questions

1. **A new node or a side table?** Is a new `RenderNode` case the right shape,
   or should a region be an ordinary `frame` plus a host-side table keyed by
   `NodeID`? The table avoids touching every exhaustive switch, but hides the
   region from the IR, MLIR, and any future inspector.
2. **Leaving focus.** How does Tab leave a native view that consumes Tab
   itself (a text view, a 3D viewport with key bindings)? Options are a
   reserved escape chord, host-level key interception, or accepting that the
   application must resign first responder.
3. **Overlays.** Do Gama overlays ever need to draw above a native region? If
   they do, the host needs a second, transparent drawing layer above attached
   views.
4. **Sub-cell placement.** Is cell-grid placement acceptable for the first
   consumer, or does the region need point-precise frames, which the
   cell-based layout can't express today?
5. **Other backends.** Should the Embed C ABI publish regions
   (`gama_embed_v1_region_*` or a new symbol family), and should the WASM host
   publish them as positioned DOM slots so a browser embedder can mount a
   canvas? Either would be a public-ABI change.
6. **Is amending ADR 0001 acceptable at all?** This is the owner's decision.
   The alternative is to keep Gama pure and build the Studio shell natively
   around a Gama host, with no region inside Gama.
7. **Platform scope.** Should AppKit and UIKit ship together, or macOS first
   with iOS and visionOS following, given the platform gate compiles
   `GamaAppleUI` for all of them?
