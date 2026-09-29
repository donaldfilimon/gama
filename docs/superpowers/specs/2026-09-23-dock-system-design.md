# Dock system: modular, draggable panels with native behavior

Builds on [ADR 0001](../../adr/0001-own-the-rendering.md) and, for panes
that host a native view, on ADR 0016 and the native region design (PR #107,
not yet on `main`).

**Status: proposed; nothing implemented.** The owner chose the direction on
2026-09-23 during brainstorming (the four decisions below). This spec is the
written design for review; the implementation plan
(a new file under `docs/superpowers/plans/`) follows only after it is
approved. Nothing is claimed in `docs/Capabilities.md` until an
implementation has evidence at the layer that evidence supports.

## Why

Gama apps should feel at home on iOS/iPadOS, macOS and, later, Windows, and
their panels should be modular: the user rearranges, resizes, collapses and
re-docks them, and the arrangement survives relaunch. The first consumer,
gama-studio, lays out Scene / viewport / Inspector-or-Graph / Console with
fixed cell widths and a hard-coded `compactWidth = 86` rule; its own spec
(§46 "Editor Shell") asks for panels that are "detachable/dockable in the
mature application".

What exists today, measured on `main`:

- Every backend draws the same cell grid; `DrawList` has `fillRect` and
  `text`. No split view, divider, scroll, clip, drag and drop, theme or
  idiom system exists.
- `InputEvent.pointer(Point, pressed: Bool)` is the entire pointer model.
  `FrameHost.handle` fires the topmost `InteractiveRegion` on press and
  ignores release. There is no move, drag, hover, scroll, modifier or
  multi-touch input, and `GamaHostView` forwards no `mouseDragged`,
  `touchesMoved` or `scrollWheel`.
- There is no Windows GUI backend; Windows is the console backend in
  `GamaTUI` (see the
  [native desktop backends draft](drafts/2026-09-22-native-desktop-backends-draft.md)).

## Decisions taken with the owner

1. **Native behavior, Gama look.** ADR 0001 stands: panels, tabs and
   dividers are Gama-drawn. "Blending in" means per-platform behavior: drag
   thresholds, hover feedback, mouse/trackpad/touch/pen/long-press input,
   platform shortcuts and per-idiom default layouts. A theme or design-token
   layer is a separate, later spec.
2. **First slice is the framework dock system plus gama-studio adopting it**,
   with saved layouts.
3. **Phones get a fixed idiom layout**, not free docking: one primary pane
   plus the other panels as switchable tabs over a bottom sheet, rearranged
   only by reordering tabs. iPad, macOS and wide terminals get full
   split/drag docking.
4. **No Windows GUI in this spec** (no Windows Swift 6.5-dev toolchain). The
   portable core must work keyboard-only on the Windows console backend.

## The architecture: a library over the existing IR

`GamaDock` is a new portable target that composes existing nodes. It adds no
`RenderNode` case.

Two shapes were considered:

- **A, a library on existing primitives (chosen).** A divider is a one-cell
  `.interactive` region whose drag writes a `@Reactive` size; the next `pump`
  lays out again. Tabs are focusable interactive regions. Drop zones and the
  drag ghost are `ZStack` overlays of `fillRect` and a label, sized from
  solved rects.
- **B, new `RenderNode.split` / `.tabs` cases.** Cleaner measurement, but it
  adds a case to `measure`, `flexMinimum`, both `flexPriority` functions,
  `layout`, `CellPainter.draw` and `GamaMLIR/Lowering.swift`, each exhaustive
  on purpose. It needs the same pointer work as A and still has to choose
  visible tabs at build time. It buys nothing A lacks.

What A must do itself, because of how `Layout.swift` works today:

- `flexPriority(along:)` always yields `.flexible(weight: 1)`, so stacks
  cannot share space by weight. The dock solves its own geometry with a
  pure `DockSolver.solve(_ layout: DockLayout, in: Size)` and emits
  `.frame(width:height:)` per pane.
- Nothing clips (`putText` wraps past a frame, `CellBuffer` clips only at the
  grid edge), so tab-strip overflow is resolved at build time: truncate
  labels, then fold the rest into a `+N` overflow tab.
- `surfaceSize` is the whole surface. `DockContainer(header:footer:…)` is a
  primitive (`Body = Never_`): it renders header and footer, measures them
  with `LayoutEngine.measure`, gives the remainder to the solver and
  assembles the vertical stack itself, so geometry is exact on the first
  frame.

## 1. Pointer input model (GamaCore)

A new `PointerGesture.swift` in `Sources/GamaCore`, and ADR 0017 "Pointer gestures
are host-owned".

**Event.** One additive case, `InputEvent.pointerEvent(PointerEvent)`:

```swift
public struct PointerEvent: Hashable, Sendable {
    public enum Phase: Hashable, Sendable { case down, move, up, cancel, hover, scroll, stationary }
    public enum Kind: Hashable, Sendable { case mouse, touch, pen }
    public struct Modifiers: OptionSet, Hashable, Sendable { /* shift, control, option, command */ }
    public var phase: Phase
    public var location: Point
    public var kind: Kind
    public var button: Int          // 0 primary, 1 secondary, 2 middle
    public var modifiers: Modifiers
    public var scroll: Point        // delta in cells / lines
    public var pointerID: Int
    public var timestampMillis: UInt64?
}
```

`.pointer(p, pressed:)` stays and `FrameHost` maps it to a mouse down or up,
so no consumer breaks. The only `switch` over `InputEvent` (in
`FrameHost.handle`) has a `default`. The code stays Embedded-safe
(`check-embedded.sh` compiles GamaCore alone).

**Registration**, beside `registerKeyHandler` on `BuildContext` and
`HostActionStore`: `registerPointerHandler(NodeID, (PointerGesture) -> Bool)`,
`registerDropTarget(NodeID)`, and `requestFocus(NodeID)` (honored when `pump`
reconciles focus; needed for F6 pane cycling).

**Recognition lives in `FrameHost`.** `PointerGesture` phases: pressed, tap,
dragBegan, dragMoved, dragEnded, cancelled, longPress, hover, scroll, each
with start point, location, translation, kind, modifiers and the drop target
under the pointer. A down on a region with a handler captures it: every move
and release goes to that region until release. Escape, a lifecycle event
(window resigns key), an explicit `cancel`, or the captured node vanishing on
rebuild cancels the drag. `FrameHost` tracks `hoveredID`, exposes it as
`EnvironmentValues.hoveredID`, and marks the host dirty only when it changes.
Regions without a pointer handler keep today's activate-on-press, so every
existing golden holds.

**Idiom policy.** `InteractionIdiom` = phone, pad, desktop, terminal, vision,
supplied by the host at creation. `FrameHost` owns the table:

| Idiom | Drag threshold | Long press |
|---|---|---|
| desktop (mouse, pen) | 1 cell | 500 ms |
| terminal | 1 cell | none |
| pad (touch) | 2 cells | 400 ms |
| phone (touch) | drag only after long press (tab reorder) | 500 ms |

Long press is timestamp-driven: while a press is held `FrameHost` exposes
`pointerDeadlineMillis`, and a host only delivers a `stationary` sample at
that time. Hosts translate; they never decide, so behavior cannot fork per
backend.

## 2. Backend translation

Pure event mapping, one phase of work:

- **`GamaAppleUI/GamaHostView.swift`.** AppKit: `mouseDragged`, `mouseMoved`
  (tracking area in `commonInit` / `updateTrackingAreas`), `mouseExited`,
  right and other mouse buttons, `scrollWheel` with precise deltas
  accumulated into cells, `modifierFlags`, `event.timestamp`. UIKit:
  `touchesMoved` tracking the first touch by identity, `UITouch.type` to
  kind, `UIHoverGestureRecognizer` for iPad pointer hover, a scroll pan
  recognizer. A one-shot timer delivers the deadline sample.
- **`GamaDraw/TerminalCapabilities.swift`** adds `?1002h` (button-held
  motion) to enable and disable. **`GamaTUI/Terminal.swift`** decodes SGR
  button bits (button, +4 shift, +8 alt, +16 ctrl, +32 motion, 64-67 wheel);
  the Windows console translator handles `MOUSE_MOVED` and `MOUSE_WHEELED`
  and takes control-key state for modifiers.
- **`GamaWASM/WASMHost.swift` + `WebHost/gama.js`**: a new
  `gama_web_v3_pointer_event(...)` export (v1 and v2 kept), Pointer Events
  with `setPointerCapture`, and `wheel`.
- **`GamaEmbed/CInterface.swift`, `GamaEmbedABI/include/GamaEmbed.h`,
  `Examples/CEmbed/main.c`**: additive `gama_embed_v1_pointer_event` and
  `gama_embed_v1_pointer_deadline` plus `GAMA_EMBED_POINTER_*` constants;
  `abi_version` stays 1 and `main.c` exercises both (the C-ABI gate builds it
  with `-Werror`).

## 3. The dock model (`Sources/GamaDock`)

Standard library only; depends on GamaCore; registered in
`check-boundaries.sh`, `portable-global-state.py` and `package-graph.py`.
ADR 0018 "Docking is a library over existing IR".

**Layout tree.**

- `PanelID(rawValue:)`, restricted to `[a-z0-9._-]` so the text format needs
  no escaping.
- `indirect enum DockNode { case split(axis: Axis, children: [DockNode], sizes: [DockSize]); case tabs(panels: [PanelID], selected: Int, collapsed: Bool) }`
- `DockSize = .cells(Int) | .weight(Int)`: side panels keep their cell width
  when the window resizes; the center takes the weight.
- `PanelSpec` (title, minimum size, `hostsNativeContent`, content builder) is
  supplied by the app and never serialized.

**Solver.** `DockSolver.solve` is pure: it allocates `.cells` first, clamps
to minimums, shares the rest by weight, and returns pane, divider and
tab-strip rects. A collapsed group shrinks to its one-cell header.

**Operations.** `DockOp` = `movePanel(PanelID, to: DropTarget(anchor:
PanelID, zone: center|leading|trailing|top|bottom, index:))`, `setSizes`,
`setCollapsed`, `select`, `reorderTab`. `apply` returns the new layout and an
inverse op. Normalization drops empty groups, unwraps single-child splits and
merges same-axis nested splits. Invariant: every registered panel appears
exactly once. Groups are addressed by an anchor `PanelID`, not a path, so
addresses survive other edits.

**Keyboard equivalents**, each an `ActionID` (the app chooses the prefix):
pane next/previous (F6), tab next/previous, tab move left/right, split
grow/shrink, collapse, move the active panel to the leading/trailing/top/
bottom neighbor, and layout reset. Dividers and tabs are focusable and take
arrows (one cell), Page Up/Down (10%) and Home/End, because `FrameHost`
offers arrow keys to the focused handler before spatial focus moves. This is
the accessibility path and the entire Windows-console path.

**Idiom defaults.**

- desktop and terminal: Scene 26 cells, center by weight, Inspector and Graph
  as one tab group of 30 cells, console full width at the bottom. This is
  gama-studio's current geometry.
- pad: the same with the console collapsed.
- phone: `CompactLayout(primary:tabs:selected:)`, the primary pane plus a
  bottom tab bar and sheet; tabs reorder only (long-press drag, or the tab
  keys).
- `DockPresentation.resolve(idiom, size)` selects compact on phones and on
  any surface narrower than the sum of panel minimums. This derived rule
  replaces gama-studio's `compactWidth = 86`.

**Persistence format** (no Foundation in the portable core): a line-oriented
text encoding, pre-order with explicit child counts.

```
gama-dock 1
layout desktop
split v 2
 w10000 split h 3
  c26 tabs 1 sel=0 col=0 scene
  w10000 tabs 1 sel=0 col=0 viewport
  c30 tabs 2 sel=0 col=0 inspector graph
 c8 tabs 1 sel=0 col=0 console
compact primary=viewport tabs=scene,inspector,graph,console sel=-
end
```

(Illustrative; the goldens pin the exact encoding of each default.) Decoding
is strict and fails closed: a wrong header, a version other than 1,
truncation, a duplicate or unknown panel, a negative size or trailing junk
returns `nil`, and the caller uses the default layout. Registered panels
missing from an otherwise valid file are re-inserted at their default
position.

## 4. Native regions inside panes

`GamaHostView` keys attached views by `NativeRegionID` and only moves their
frames, so a pane can move without re-attaching its view. The dock adds:

1. **Stable identity.** Each panel renders under a scope derived from its
   `PanelID` (an FNV-1a hash in GamaDock; `NodeID` offers only `child(Int)`
   today), so a moved viewport keeps its `NodeID`, focus, `@Reactive` state
   and first-responder handoff.
2. **One build per frame.** A panel's content is built at most once per
   frame; the drag ghost and previews are label-only, so no second
   `NativeRegion` trips `duplicateNativeRegionIDs`.
3. **Hidden tabs are not built**, so the host hides their views. On phones
   the viewport is the primary pane and always built.
4. **Chrome carries the interaction.** Drags start only from tab or title
   chrome, never from inside a native view; drop highlights for native panes
   paint on the pane's chrome rows, since the native view covers its cells.

This section lands as an addendum to ADR 0016, after PR #107 merges.

## 5. gama-studio adoption

- `StudioRootView` becomes `DockContainer(header: toolbar, footer:
  statusLine, layouts: …, panels: studioPanels, idiom: …)`. `compact(width:)`,
  `compactWidth` and `compactPanelHeight` are deleted; Inspector and Graph
  become one tab group and `studio.graph.toggle` selects the Graph tab; the
  fixed `width:` parameters leave `HierarchyPanel`, `InspectorPanel` and
  `GraphPanel`.
- `StudioLayoutStore` (app layer, Foundation allowed) persists
  `Application Support/GamaStudio/layouts.gamadock`: load at start, save
  coalesced after operations and on backgrounding. A failed decode loads the
  default and posts a status notice. A Reset Layout command performs the
  reset action.
- The default layout reproduces today's geometry, so painted-text tests at
  120x40 and the viewport-size assertions hold; expect small edits where a
  test reads the Inspector/Graph titles.

## Error handling

- Decode failures fall back to the idiom default and are reported, never
  crash, never partially apply.
- An operation that would break the exactly-once invariant or violate
  minimum sizes is rejected with no change; the inverse of every accepted op
  restores the previous layout exactly.
- A drag whose captured node disappears is cancelled and the layout is
  untouched.
- A layout that no longer fits (window shrink) is re-solved with minimums
  first; below the sum of minimums the presentation turns compact rather than
  overlapping panes.

## Testing

Swift Testing only; value goldens, as the rest of the suite.

- `PointerGestureTests`: threshold per idiom, capture, cancel paths, tap vs
  drag, long-press deadline, hover dirtiness, `.pointer` compatibility.
- Backend: SGR decode cases, Windows console translation, `?1002h` in
  `TerminalCapabilityTests`, an AppKit host drag test, the C-embed example
  and the WASM browser smoke.
- `DockOpsTests` (every op's inverse restores the layout), `DockSolverTests`,
  `DockCodecTests` (goldens per default layout, round trip after each op, a
  malformed-input corpus), `DockRenderTests` (`CellSerializer` goldens at
  120x40, 80x24 and a compact 60x30), `DockKeyboardTests` (every operation
  reachable through `FrameHost.handle` with keys only), `DockPointerTests`.
- Native regions: a moved viewport keeps its `NodeID` and focus, and the host
  updates the attached view's frame.
- gama-studio: default layout equals the legacy geometry, compact at 60x30,
  store round trip and corrupt file, viewport move keeps the ARView attached,
  divider drag from synthetic pointer events; `MIN_TESTS` rises accordingly.

## Phases

One Gama PR per phase; gama-studio has no remote and commits on `main`.

1. Pointer model and ADR 0017.
2. Backend translation.
3. `GamaDock` target and ADR 0018.
4. Native regions in panes and the ADR 0016 addendum (requires PR #107 on
   `main`).
5. gama-studio: bump its gama pin from `2ef325c` to the `main` revision that
   holds phases 1-4, then adopt.

PR #107 should merge before phase 1: phases 1 and 2 edit the same
`FrameHost.swift` and `GamaHostView.swift`. If it must stay open, phases 1-2
stack on its branch.

Every Gama phase is gated locally by `scripts/check-apple.sh` and then
`scripts/check.sh` (all gates), reading each verdict line; hosted runs are
billing-locked and count as unmeasured. gama-studio is gated by
`tools/check.sh` (`check.sh: PASSED`).

## Out of scope

Theme and design tokens; a Windows GUI backend; detached floating panel
windows; dragging assets into the viewport (gama-studio spec Phase 5).
