# Native presentation: Gama views as AppKit controls (sub-project 1)

Implements [ADR 0017](../../adr/0017-native-presentation.md), which supersedes
the widget clause of ADR 0001 and the "What 0001 still forbids" section of
ADR 0016.

**Status: Draft for owner review (2026-09-23). Nothing is built.** Branch
`feat/native-presenters`, stacked on `docs/native-surface-draft` (PR #107,
which carries native regions and ADR 0016). No row is added to
`docs/Capabilities.md` until an implementation has evidence at the layer it
supports.

## Why, and where this sits

The owner wants Gama apps (first the ABI operator app, later a consumer
Abbey shell) to blend in on macOS, iOS, Android, and Windows with **real
platform controls**, and to have **modular, draggable panels** that behave
the same everywhere. Decisions taken in conversation on 2026-09-23:

- Stack: Gama (not per-platform native UIs over a Rust core, not Tauri).
- "Blending in" means real platform controls (option a), not Gama-drawn
  cells styled like the platform, and not a native-region hybrid.
- Layout: **Gama owns all layout in points and the platform measures**
  (option 1), so docking and dragging are one tested implementation.

That is six sub-projects, each with its own spec, plan, and review:

| # | Sub-project | Repo | Depends on |
| - | ----------- | ---- | ---------- |
| 1 | **Native presentation on macOS (this spec)**: metrics-driven layout, control descriptors, AppKit presenter | Gama | PR #107 |
| 2 | Dock model: panels, splits, tabs, drag handles, drop targets, persisted layouts, pure Gama | Gama | 1 |
| 3 | More native hosts: UIKit (iOS), Android Views over the JNI backend, Windows native controls (Win32 or WinUI; the Swift projection is unresolved, and the Windows 6.5-dev toolchain is missing unless a 6.4.x exception is accepted), and shell menus routed to `ActionID` | Gama | 1 |
| 4 | abi ↔ Gama bridge: how a Swift app reaches the Rust runtime, locally and from a phone | abi | 1 |
| 5 | ABI operator app: dashboard, WDBX, agents, GPU, studio as dockable panels | new app repo or abi | 2, 4 |
| 6 | Consumer Abbey shell on the same foundation | app repo | 5 |

Sub-project 1 is macOS-only because it is the one platform where every step
can be built, run, and verified on this machine.

## Goals and non-goals

**Goals.** A `GamaNativeHostView` (AppKit) that presents any Gama app with
native `NSTextField` labels and fields, `NSButton` push buttons and
checkboxes, `NSProgressIndicator`, `NSBox` separators, and plain `NSView`
containers, at frames computed by `LayoutEngine` in points, with proportional
system text measured by AppKit. Actions, text edits, toggles, keyboard focus,
Tab order, and VoiceOver work through the native controls. Native regions
(ADR 0016) keep working inside it. Every existing app, test, and backend is
unchanged by default.

**Non-goals (later sub-projects).** Docking and dragging (2). UIKit,
Android, Windows, and menu-bar routing (3). Scroll views: Gama has no
`ScrollView` today and adding one is a portable-API change for its own spec.
Dynamic Type, right-to-left, and custom control styling.

## Decision 1: layout takes its measurements from the host

`LayoutEngine` keeps its integer geometry (`Point`, `Size`, `Rect`,
`ProposedSize` stay `Int`). What changes is **who measures and what one unit
means**. A new portable struct of closures in `GamaCore`. It is not a
protocol, because `GamaCore` compiles for Embedded Swift, which has no
existentials, and making `LayoutEngine`, `FrameHost`, and `HostPump` generic
would ripple into every backend. A struct of closures is the house pattern
already (`BuildContext.registerAction`, `registerNativeRegion`):

```swift
/// Supplies the measurements `LayoutEngine` cannot compute itself.
public struct LayoutMetrics {
    /// Size of text drawn with a style, wrapped to a maximum width when given.
    public var textSize: (String, TextStyle, Int?) -> Size
    /// Converts an authored length in cells to layout units on one axis.
    public var units: (Int, Axis) -> Int
    /// Main-axis thickness of a divider, in layout units.
    public var dividerThickness: Int
    /// Intrinsic size of a registered control, or nil to measure its child.
    public var controlSize: (NodeID, ProposedSize) -> Size?
    /// Cell metrics: today's measurements, unchanged.
    public static var cell: LayoutMetrics { get }
}
```

- **`LayoutMetrics.cell`** is the default. It returns `TextLayout.size`, the
  identity for `units`, 1 for dividers, and nil for controls, so every
  current caller produces **byte-identical** layouts. The existing layout,
  P1 layout, FrameHost, DrawList, WASM, and TUI tests are the parity oracle.
- `LayoutEngine.measure`/`layout` gain a `metrics:` parameter defaulting to
  `.cell`. Every authored length (stack spacing, padding insets,
  `frame(width:height:)`, `spacer(minLength:)`, the ends of `flexFrame`
  other than `.max`) is converted through `units(cells:axis:)` at the point
  of use. Flex distribution (ADR 0013) is unchanged: it already works on
  arbitrary integers.
- `.text` leaves measure through `textSize`. An `.interactive` node asks
  `controlSize(for:proposal:)` first and falls back to measuring its child.
- `FrameHost` stores its metrics, set at `init` (default `.cell`), and uses
  them in `buildFrame`. **`surfaceSize` stays in cells** (ADR 0017 rule 3):
  a native host reports its bounds divided by its cell size, so
  `VirtualizedList` and other author code keep their meaning.
- The core stays stdlib-only, integer, and Embedded-compilable. Hosts round
  platform measurements up to whole points before returning them. The
  Embedded artifact grows by the new code; the plan records the new size
  and must stay inside the baseline tolerance or update the baseline
  deliberately with the reason.

**Rejected:** a second `PointLayoutEngine` (two flex implementations to keep
in step) and making geometry generic or floating point (touches every public
geometry type, and Embedded forbids libm rounding in `GamaCore`).

## Decision 2: controls describe themselves through a side table

Following the action and native-region pattern, controls register a portable
descriptor instead of adding `RenderNode` cases:

```swift
/// What a native host needs to present a control; closures write back.
public enum ControlDescriptor {
    case button(title: String?, isEnabled: Bool)
    case toggle(title: String, isOn: Bool, isEnabled: Bool)
    case textField(placeholder: String, text: String, isEnabled: Bool,
                   setText: (String) -> Void)
    case progress(fraction: Double?, label: String?)
}
```

- `BuildContext` gains `registerControl: (NodeID, ControlDescriptor) -> Void`,
  a trailing `init` parameter defaulting to a no-op, and `FrameHost` keeps a
  per-build table cleared in `beginBuildPass()`, exactly like
  `registerNativeRegion`.
- `Button`, `Toggle`, `TextField`, and `ProgressView` register a descriptor
  in `render(in:)` and **still return the same `RenderNode` as today**, so
  the cell path, MLIR, and DrawList output do not change. The one exception
  is `ProgressView`, which today lowers to a bare `.text` with no identity to
  key on. It gains an `.interactive(id:, focusable: false)` wrapper around
  the same text. `CellPainter` paints an `interactive` node as its child, so
  its cells are unchanged. Its MLIR output does change (it gains the
  interactive wrapper), so the plan updates any affected MLIR expectations
  deliberately and adds a test that `FrameHost` pointer hit-testing treats a
  node with no registered action as a no-op.
- `button(title:)` carries the label's text when the label compiles to a
  single text run, and nil otherwise. A nil title presents as a clickable
  container whose label subtree is presented natively inside it.
- Activation, toggling, and editing reuse the existing registrations: the
  native host calls a new `FrameHost.activate(_ id: NodeID)`, which runs the
  action registered for that node, and `setText` writes the `TextField`
  binding directly. No second action system is introduced.

## Decision 3: a portable presentation tree and diff

The laid-out tree is converted into the minimal tree of views a native host
needs, and successive frames are diffed. Both steps are stdlib-only, live in
a new `Sources/GamaCore/NativePresentation.swift`, and are tested without
AppKit.

- **Which nodes become views.** `text`, `divider`, `background`, `border`,
  and `interactive` produce a view. `stack`, `overlay`, `group`, `spacer`,
  `padding`, `frame`, `flexFrame`, and `styled` produce none: they only
  contribute frames and inherited style. `empty` produces nothing.
- **Identity.** An `interactive` node uses its `NodeID`. Every other
  view-producing node uses the path of child indices from the root of the
  laid-out tree, mixed the way `NodeID.child(_:)` is.
- **Shape.** `PresentedNode` holds identity, kind (label, separator,
  container, control with descriptor, native region), the frame **relative
  to its nearest view-producing ancestor**, the resolved `TextStyle`, and
  its children in paint order.
- **Diff.** `PresentationDiff.between(old, new) -> [PresentationOp]`, where
  the ops are `insert(id, kind, parent, index)`, `update(id, properties)`,
  `setFrame(id, rect)`, `move(id, parent, index)`, and `remove(id)`. A kind
  change is a remove then an insert. The op list is deterministic, so tests
  pin it exactly.

## Decision 4: the AppKit host

A new `GamaNativeHostView` in `GamaAppleUI`, in its own files so
`GamaHostView.swift` (850 lines on the base branch) does not grow:

- **Session.** It owns a `HostPump` exactly like `GamaHostView`, but calls
  `advance()` and never paints cells. It builds the presentation tree,
  diffs it, and applies the ops to real subviews (`isFlipped = true`, frames
  in points).
- **Metrics.** `AppKitLayoutMetrics` measures text with
  `NSAttributedString.boundingRect` in the system font (caching by string,
  style, and width), measures controls with a reusable prototype control's
  `fittingSize`, and converts cells to points with a cell size probed once
  from the system font. All results are rounded up to whole points.
- **Mapping.**

  | Presented kind | AppKit view |
  | -------------- | ----------- |
  | label | non-editable, non-bezeled `NSTextField`, wrapping at its frame width |
  | separator | `NSBox` of type `.separator` |
  | container (`background`, `border`) | layer-backed `NSView` (fill color; border width and color) |
  | `button` with title | `NSButton`, push style |
  | `button` without title | clickable container view hosting the label subtree |
  | `toggle` | `NSButton`, checkbox style |
  | `textField` | editable `NSTextField` with placeholder |
  | `progress` | `NSProgressIndicator` (determinate bar, or spinner when fraction is nil) |
  | native region | the application's attached view (ADR 0016), or its fallback presented natively |
  | other `interactive` | focusable container forwarding keys to `FrameHost.handle(.key)` |

- **Style.** Text with no explicit color uses `NSColor.labelColor`, and
  containers with no explicit background are transparent, so light and dark
  mode follow the system. Explicit Gama colors map to fixed `NSColor`s. Bold
  and italic map through the system font's symbolic traits. The cell-only
  focus style (cyan highlight) is ignored: AppKit draws its own focus ring.
- **Events.** Buttons and checkboxes call `FrameHost.activate`. Text fields
  call `setText` from `controlTextDidChange`. Keys that reach a generic
  container go to `FrameHost.handle(.key)`. Pointer hit-testing is AppKit's.
- **Focus.** `FrameHost` stays the source of focus order. The host sets
  `nextKeyView` in Gama's focus order, reports first-responder changes back
  through a new `FrameHost.focus(_ id: NodeID)`, and makes the matching
  control first responder when Gama moves focus.
- **Accessibility.** Native controls expose their own roles, labels, and
  values. The host view is a plain container: the cell `AccessibilitySnapshot`
  adapter is not used on this host.
- **Shell.** `GamaAppleShell` gains an opt-in to use `GamaNativeHostView` as
  a window's content view, sized in points. Menu routing is sub-project 3.
- **Demo.** `GamaAppleDemo` gains a `--native` flag that shows every mapped
  control, so the result can be seen and used, not only tested.

## Error handling

- A duplicate control or region `NodeID` in one frame follows the existing
  `validateIdentities` and `duplicateNativeRegionIDs` behavior: it is
  reported, and the first registration wins.
- A text measurement AppKit cannot produce (empty or invalid attributed
  string) falls back to `LayoutMetrics.cell` scaled by the cell size, so layout
  never stalls.
- A presentation op that references an unknown id is a programming error: a
  debug assertion and a skipped op in release, never a crash in shipping
  code.
- **Focus re-entrancy.** Focus is two-way: Gama moves first responder, and
  first-responder changes call `FrameHost.focus(_:)`, which rebuilds. To stop
  a loop, `focus(_:)` is a no-op when the node is already focused, and the
  host ignores first-responder notifications it caused itself while applying
  a frame.
- **Text editing forks here, deliberately.** On a native host,
  `NSTextField` owns editing, caret, selection, and IME. `TextField`'s
  registered key handler and its ADR 0014 cursor slot stay registered but
  are dormant: only Tab and Shift-Tab reach `FrameHost`. The cell path keeps
  using them unchanged.

## Testing

Swift Testing only (ADR 0003). Every new public declaration has a `///`
comment (doc-coverage gate).

- **Parity (portable).** With `LayoutMetrics.cell`, every existing layout, FrameHost,
  DrawList, TUI, and WASM test passes unchanged. A new test lays out every
  view in the catalog both through the old call and the metrics call and
  asserts identical `LaidOutNode` trees.
- **Metrics (portable).** A fake metrics object with proportional widths and
  non-unit `units(cells:axis:)` proves that text size, spacing, padding,
  fixed frames, dividers, and control sizes flow through stacks and flex
  distribution as specified.
- **Descriptors (portable).** Each control registers the right descriptor,
  disabled controls register `isEnabled: false`, `setText` writes the
  binding, `FrameHost.activate` runs the node's action, and cell output is
  byte-identical before and after.
- **Presentation tree and diff (portable).** Which nodes become views,
  relative frames, identity stability across rebuilds, and exact op lists
  for insert, update, move, reorder, kind change, and remove.
- **AppKit (offscreen, following `AppleHostTests`).** Each descriptor
  produces the mapped control at the computed frame. `performClick` runs
  the action. Typing updates the binding. Toggling flips state. Tab follows
  Gama focus order. Accessibility roles are button, checkbox, text field,
  and static text. A native region attaches inside the native host. Light
  and dark appearance both resolve label colors.
- **Gates.** `scripts/check-apple.sh` (build, test, release), then the full
  `scripts/check.sh`. Its boundaries and portable-import gate must stay green
  with no new exceptions, and the Embedded gate must stay under its size
  baseline. Hosted jobs are unmeasured while the account billing lock holds,
  and nothing is claimed from them.

## Risks and what the plan must settle

- **Layout cost.** Text measurement moves from table lookups to AppKit calls.
  The metrics cache is keyed by string, style, and width. The plan
  measures a large tree before and after, and records the numbers in
  `docs/Performance.md` as local, not a gate.
- **Parity of the metrics refactor.** Every authored length must go through
  `units(cells:axis:)` exactly once. The parity test over the whole catalog
  is the guard, and it lands before any native code.
- **Buttons with rich labels.** A container button is less native than
  `NSButton`. That is acceptable for sub-project 1. If the operator app
  needs icon buttons, the descriptor gains an image case later.
- **Index-path identity (v1 limitation).** Non-interactive views are keyed
  by their index path, so a conditional insert shifts later siblings and the
  diff emits remove and insert where a move was meant. Labels re-created
  that way flicker for a frame but hold no state. Interactive nodes keep
  stable `NodeID`s, so text fields never lose their field editor. Stable
  identity for plain nodes is a later refinement if the operator app shows
  the flicker.
- **Stacking on PR #107.** This branch is based on native regions. If #107
  changes before it merges, this branch rebases onto it; it does not merge
  `main` back into it.
