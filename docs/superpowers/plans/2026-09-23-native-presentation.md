# Native presentation on macOS: implementation plan

**Spec:** [`docs/superpowers/specs/2026-09-23-native-presentation-design.md`](../specs/2026-09-23-native-presentation-design.md)
(approved by the owner on 2026-09-23), with [ADR 0017](../../adr/0017-native-presentation.md).
Branch `feat/native-presenters`, stacked on `docs/native-surface-draft` (PR #107).
Execution: subagent-driven development, one task per commit set, test first.

## Global Constraints

- **Portable targets stay portable.** `GamaCore`, `GamaPlugin`, `GamaDraw`,
  `GamaEmbed`, `GamaMLIR` import nothing but the standard library (no
  Foundation, AppKit, UIKit, Darwin, Glibc, WinSDK, Synchronization), hold
  no process-global state, and `GamaCore` must still compile for Embedded
  Swift (`scripts/check-embedded.sh`): **no existentials (`any P`), no
  libm (`.rounded()`, `ceil`)**, integer geometry only.
- **Cell parity is absolute.** With `LayoutMetrics.cell`, every existing
  layout, `CellPainter`, `DrawList`, TUI, WASM, and MLIR output is
  byte-identical to before, except `ProgressView`'s node shape (Task 4),
  whose painted cells are still identical.
- **No new `RenderNode` case, no new MLIR op, no DrawList wire change.**
- **Side tables are last-wins** within one build pass, matching
  `publishNativeRegions` (`FrameHost.swift:239`).
- **Authored lengths are cells.** Spacing, padding, fixed frames, spacer
  minimum length, flexFrame finite bounds, border thickness, and
  `surfaceSize` are cells in the public API; only `LayoutMetrics.units`
  converts them.
- **Swift Testing only** (ADR 0003). Every new `public` declaration has a
  `///` doc comment (doc-coverage gate). AppKit code is inside
  `#if canImport(AppKit)` (GamaAppleUI also builds for UIKit) and must pass
  strict memory safety (warnings are errors in `strictLibrary` targets).
- **Toolchain.** `unset TOOLCHAINS; /usr/bin/xcrun --toolchain
  org.swift.65202608211a swift test --scratch-path /private/tmp/gama-native-$USER
  --filter <StructName>`. `--filter` matches the struct name; a filter that
  matches nothing exits 0, so always confirm the executed test count is
  above zero. Never build in `~/Desktop/Gama` (another session owns it).
- **Commits.** Conventional Commits, ending with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **No capability claims** in `docs/Capabilities.md` beyond the evidence a
  task actually produced.

## Task 0: Publish and amend the spec

Controller task (no implementer).

1. Push `feat/native-presenters` and open a draft PR with base
   `docs/native-surface-draft`.
2. Amend the spec, docs only:
   - Closure properties carry no argument labels: write `units(cells, axis)`
     and `controlSize(id, proposal)`.
   - Add the border's hard-coded `2` and `EdgeInsets(all: 1)`
     (`Layout.swift` :44–50, :140–141, :174–175) to the authored lengths
     converted through `units`. The `crossMax == 0 → 1` floor (:124) stays 1
     layout unit.
   - Duplicate control registrations: the **last** wins, like native regions.
   - `Toggle` renders through `Button`, then registers `.toggle`; last-wins
     replaces Button's `.button` entry for that `NodeID`.

## Task 1: LayoutMetrics and metrics-driven layout

Files: create `Sources/GamaCore/LayoutMetrics.swift`; modify
`Sources/GamaCore/Layout.swift`; create `Tests/gamaTests/LayoutMetricsTests.swift`.

1. **Tests first.** `LayoutMetricsParityTests`: for a catalog covering every
   `RenderNode` case (text incl. wide/zero-width graphemes and wrapping,
   every stack axis/spacing/alignment, overlay, group, spacer with
   minLength, divider on both axes, padding, border with and without title,
   background, frame, flexFrame with finite and `.max` bounds, styled,
   interactive, and nested flex mixes), `LayoutEngine.layout(node, in:)` and
   `LayoutEngine.layout(node, in:, metrics: .cell)` produce equal
   `LaidOutNode` trees, and `measure` agrees too. `LayoutMetricsScalingTests`:
   a fake `LayoutMetrics` with `units = cells * 8` horizontally and
   `* 17` vertically, text width = 7 per character and height 17 per line,
   divider thickness 1, and a fixed `controlSize` for one `NodeID`, asserting
   exact frames for spacing, padding, border insets, fixed frames, flexFrame
   bounds, text, dividers, control sizes, and flex distribution.
2. `public struct LayoutMetrics` exactly as the spec shows (closure
   properties `textSize: (String, TextStyle, Int?) -> Size`,
   `units: (Int, Axis) -> Int`, `dividerThickness: Int`,
   `controlSize: (NodeID, ProposedSize) -> Size?`, a public memberwise
   `init`, `public static var cell`).
3. Thread `metrics` through `measure`, `measureStack`, `flexMinimum`,
   `layout`, `layoutStack` (`Layout.swift` :21, :85, :131, :165, :228). Public
   `measure(_:proposal:)` and `layout(_:in:)` keep their signatures and
   forward `.cell`; add `measure(_:proposal:metrics:)` and
   `layout(_:in:metrics:)`.
4. Convert every authored length through `metrics.units` at the point of use
   (spacing :89 :236 :330; spacer :29 :133; padding :35 :137 :170; border :44
   :140 :174; frame :56 :183; flexFrame finite bounds :61 :135, never the
   `.max` sentinel). `.text` measures through `metrics.textSize` (:26);
   dividers use `metrics.dividerThickness` (:32 :95 :249); `.interactive`
   asks `metrics.controlSize(id, proposal)` first (:52 :142 :178) and
   otherwise measures its child. Padding/border insets are converted per
   edge with the matching axis.
5. Run the new suites plus `LayoutTests`, `P1LayoutTests`, `DrawListTests`.

## Task 2: FrameHost carries metrics

Files: `Sources/GamaCore/FrameHost.swift`; tests in `Tests/gamaTests/LayoutMetricsTests.swift`
(new suite `FrameHostMetricsTests`).

1. Test first: a `FrameHost(app:metrics:)` with the scaling fake lays out a
   small app at point frames; the `size` passed to `pump` is in layout units,
   and `surfaceSize` seen by the app is that size divided per axis by
   `metrics.units(1, axis)` (integer division, divisor at least 1), so with
   `.cell` it equals the pump size exactly as today; default init equals
   `.cell`.
2. Add `metrics: LayoutMetrics = .cell` to `init(app:)` (:139) and
   `init(surface:)` (:146), store it, use it at `LayoutEngine.layout` in
   `buildFrame` (:228), and compute `surfaceSize` (:190) as in step 1.
   `HostPump` is unchanged.
3. Run `FrameHostTests`, `HostPumpTests`, `NativeRegionTests`, the new suite.

## Task 3: ControlDescriptor side table

Files: create `Sources/GamaCore/ControlDescriptor.swift`; modify
`Sources/GamaCore/View.swift`, `Sources/GamaCore/FrameHost.swift`,
`Sources/GamaCore/HostPump.swift`; create `Tests/gamaTests/ControlDescriptorTests.swift`.

1. Tests first (`ControlDescriptorBuildTests`, `ControlDescriptorHostTests`):
   a `BuildContext(registerControl:)` records registrations; `FrameHost`
   exposes the table after `pump`, clears it each build pass, and keeps the
   last registration for a duplicate `NodeID`; `HostPump.controls` mirrors it.
2. `public enum ControlDescriptor` exactly as the spec shows, plus a public
   `ControlEntry` (or tuple-free struct) pairing `NodeID` and descriptor if
   the table is exposed as an array; prefer `[NodeID: ControlDescriptor]`.
3. `BuildContext.registerControl: (NodeID, ControlDescriptor) -> Void`, a
   trailing `init` parameter after `registerNativeRegion` (`View.swift:53`)
   defaulting to a no-op, copied by `child(_:)`.
4. `HostActionStore` gains `controls`, cleared in `beginBuildPass()` (:46);
   wire it in `buildFrame` (:218). Expose `FrameHost.controls` and
   `HostPump.controls` beside `nativeRegions` (`HostPump.swift:82`).
5. `LayoutMetrics` gains `descriptorSize: (ControlDescriptor, ProposedSize) ->
   Size?` (memberwise-init parameter defaulting to a closure returning nil;
   `.cell` returns nil). In `buildFrame`, after render and before layout,
   FrameHost passes the engine a per-frame copy of its metrics whose
   `controlSize` looks the `NodeID` up in this build's control table and
   calls `descriptorSize`, falling back to the base `controlSize`. Test:
   with a fake whose `descriptorSize` returns a fixed size for `.button`, a
   `Button` inside a `FrameHost` lays out at that size; with `.cell`, layout
   is unchanged.

## Task 4: Controls register descriptors

Files: `Sources/GamaCore/Primitives.swift`; `Tests/gamaTests/ControlDescriptorTests.swift`
(new suite `ControlRegistrationTests`); `Tests/gamaTests/ProgressViewTests.swift`;
`Tests/gamaTests/FormControlTests.swift`.

1. Tests first: `Button("Save")` registers `.button(title: "Save",
   isEnabled: true)`; a button with a composite label registers
   `title: nil`; a disabled button registers `isEnabled: false`; `Toggle`
   registers `.toggle` (and no `.button` survives for its id); `TextField`
   registers `.textField` whose `setText` writes the binding;
   `ProgressView` registers `.progress` with the clamped fraction, nil
   when indeterminate if the type supports it. For each control, the cell
   buffer painted by `CellPainter` before and after is identical.
2. Internal `plainText(of: RenderNode) -> String?`: returns the string when
   the node is a single `.text` run (through `styled`/`padding` wrappers),
   trimming the single leading and trailing space `Button(_ title:)` adds
   (:280); nil otherwise.
3. Register in `Button.render` (:245; disabled path registers
   `isEnabled: false` without an action), `Toggle.render` (:408, after
   Button's render), `TextField.render` (:322), `ProgressView.render`
   (:456). `ProgressView` now returns `.interactive(id: context.id,
   focusable: false, child: <the same .text>)`; update the `guard case .text`
   helpers in `ProgressViewTests.swift:8` and `FormControlTests.swift:25–33`
   to unwrap it. Add a test that a pointer hit on the progress node is a
   no-op.
4. Run `ControlDescriptorTests`, `ProgressViewTests`, `FormControlTests`,
   `ActionTests`, `DrawListTests`, the MLIR fixture suites.

## Task 5: FrameHost.activate and FrameHost.focus

Files: `Sources/GamaCore/FrameHost.swift`, `Sources/GamaCore/HostPump.swift`;
tests in `Tests/gamaTests/ControlDescriptorTests.swift` (suite `HostActivationTests`).

1. Tests first: `activate(id)` runs the node's action and marks dirty;
   `activate` on a node with no action is a no-op; `focus(id)` moves focus to
   a focusable node and marks dirty; `focus` on the already-focused node or
   a non-focusable/unknown node changes nothing and does not mark dirty;
   both through `HostPump`.
2. `public mutating func activate(_ id: NodeID)` mirrors the pointer path
   (:359–362) without hit-testing; `public mutating func focus(_ id: NodeID)`
   sets `focusedID` (:101) only for an id in `focusables`. Add a read-only
   `public var focusedNode: NodeID? { focusedID }`. `HostPump` gets
   pass-throughs.

## Task 6: Presentation tree and diff

Files: create `Sources/GamaCore/NativePresentation.swift`,
`Tests/gamaTests/NativePresentationTests.swift`.

1. Tests first: which nodes produce views; frames relative to the nearest
   view-producing ancestor; identity (interactive → its `NodeID`, others →
   index path mixed like `NodeID.child(_:)`) stable across identical
   rebuilds; resolved inherited `TextStyle` on labels; descriptor and native
   region attached to the matching interactive node; exact op lists for
   insert, update (text or descriptor change), setFrame, move/reorder, kind
   change (remove + insert), and remove; identical trees → no ops.
2. Implement `PresentedNode` (identity, kind, frame, style, children) with
   `PresentedKind`: `label(String)`, `separator(Axis)`, `container(background:
   Color, border: BorderStyle?)`, `control(ControlDescriptor)`,
   `nativeRegion(NativeRegionID)`, `focusGroup(focusable: Bool)`.
   `PresentedNode.tree(from:controls:regions:)` and
   `PresentationDiff.between(_:_:) -> [PresentationOp]` with ops
   `insert(id:kind:parent:index:frame:)`, `update(id:kind:)`,
   `setFrame(id:frame:)`, `move(id:parent:index:)`, `remove(id:)`. Kinds
   holding closures compare by their non-closure fields.

## Task 7: AppKitLayoutMetrics

Files: create `Sources/GamaAppleUI/AppKitLayoutMetrics.swift`,
`Tests/gamaTests/AppleNativeHostTests.swift` (suite `AppKitLayoutMetricsTests`).

1. Tests first: cell size probe is positive and matches the system font;
   proportional text ("iiii" narrower than "WWWW"); wrapping at a max width
   increases height; results are whole points; the cache returns identical
   values; control sizes for a push button, checkbox, text field and
   progress bar are positive; invalid input falls back to `.cell` scaled by
   the cell size.
2. `@MainActor` factory returning a `LayoutMetrics` whose closures measure
   with `NSAttributedString.boundingRect` (system font, bold/italic traits),
   round up, cache by (string, style, width), size controls from prototype
   controls' `fittingSize`, and convert cells to points with the probed
   cell size. Inside `#if canImport(AppKit)`.

## Task 8: GamaNativeHostView

Files: create `Sources/GamaAppleUI/GamaNativeHostView.swift`,
`Sources/GamaAppleUI/NativeHostSession.swift`,
`Sources/GamaAppleUI/NativeControlMapping.swift`; tests in
`Tests/gamaTests/AppleNativeHostTests.swift` (suite `AppleNativeHostTests`).

1. Tests first, offscreen like `AppleHostTests` and the window setup in
   `AppleHostNativeRegionTests.swift:76`: each control kind appears as the
   mapped AppKit class at its computed frame; `performClick` runs the
   action; setting field text and sending `controlTextDidChange` updates the
   binding; a checkbox flips its binding; Tab order (`nextKeyView`) follows
   Gama focus order; accessibility roles are button, checkbox, text field,
   static text; label color is `labelColor` when no foreground is set and
   resolves under both aqua and darkAqua appearances; re-rendering with a
   changed title updates in place without recreating the control.
2. Implement per the spec's Decision 4 table: session owns
   `HostPump(host: FrameHost(surface:metrics:), size:)`, calls `advance()`,
   builds the presentation tree, diffs it, applies ops to subviews
   (`isFlipped = true`); events call `activate`/`setText`; first-responder
   changes call `focus`, guarded by an applying flag; the same package API as
   `GamaHostView` (`install(app:)`, `install(surface:)`, `send`, `tearDown`,
   `invalidate`).

## Task 9: Native regions in the native host

Files: `Sources/GamaAppleUI/GamaNativeHostView.swift`; tests in
`Tests/gamaTests/AppleNativeHostTests.swift` (suite `AppleNativeHostRegionTests`).

1. Tests first: attaching a view to a region places it at the region's point
   frame; detaching removes it and shows the fallback presented natively;
   focus moving onto the region hands first responder to the attached view.
2. Reuse the attach/detach contract from `GamaHostView.swift` :306–405 with
   point frames.

## Task 10: Shell opt-in and demo

Files: `Sources/GamaAppleShell/GamaShell.swift`, `Sources/GamaAppleDemo/main.swift`;
tests in `Tests/gamaTests/AppleShellTests.swift`.

1. Tests first: a coordinator created with native presentation opens a
   window whose content view is a `GamaNativeHostView` sized in points; the
   default still uses `GamaHostView`.
2. `GamaShellPresentation` (`.cells`, `.native`), an extra
   `GamaShellCoordinator(graph:presentsWindows:presentation:)` (:103)
   parameter defaulting to `.cells`, a `GamaShell.run(_:presentation:)`
   overload, and the window controller (:287) picks the host view and sizes
   the window in points. The shell talks to either host through a small
   package protocol.
3. Demo: `--native` opens the demo app natively; `--native-smoke` runs it
   headless, asserts a button, checkbox, text field, progress indicator and
   label exist, and exits 0.

## Task 11: Docs and evidence

Files: `Sources/GamaCore/GamaCore.docc/GamaCore.md`,
`Sources/GamaAppleUI/GamaAppleUI.docc/GamaAppleUI.md`, `docs/Testing.md`,
`docs/Capabilities.md`, `docs/Performance.md`,
`scripts/embedded-size-baseline.txt` (only if needed), `docs/backends/AppleUI.md`.

1. Curate `LayoutMetrics`, `ControlDescriptor`, `PresentedNode`,
   `PresentationDiff` in the GamaCore catalog and `GamaNativeHostView` in the
   GamaAppleUI catalog; add a native-host section to `docs/backends/AppleUI.md`.
2. `docs/Testing.md`: rows for the new test files, alphabetically.
3. `docs/Capabilities.md`: rows whose evidence paths this branch changed and
   that are not already `unverified` flip to `unverified` (run
   `scripts/check-evidence-freshness.sh` to find them); add a "Native
   presentation (AppKit)" row at `locally` only if the gate proves it.
4. `docs/Performance.md`: time `LayoutEngine.layout` on a large tree with
   `.cell` before and after Task 1, and with AppKit metrics; label it local,
   not a gate.
5. Run `scripts/check-embedded.sh`; if the artifact exceeds the tolerance,
   update the baseline with the reason.

## Task 12: Gate and finish

Controller task.

1. `GAMA_APPLE_SCRATCH_PATH=/private/tmp/gama-native-apple ./scripts/check-apple.sh`,
   then `./scripts/check.sh`, each to a log with `>|`, exit code checked
   against the log's verdict. Fix the first real failure, re-run, repeat.
2. Push; update the draft PR with results and the exact gate lines.
3. Report what was verified, skipped, and uncertain.
