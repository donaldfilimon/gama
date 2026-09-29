# UI scaling: text size, Dynamic Type, zoom, and responsive layout

Track 1 of the [native UI roadmap](2026-09-29-native-ui-roadmap-design.md).

**Status: proposed, awaiting owner review (2026-09-29). Nothing is built.**
No row is added to `docs/Capabilities.md` until an implementation has
evidence at the layer it supports.

## Goal

A Gama app's text can be made larger or smaller, following the platform's
setting where one exists, and the UI refits rather than clipping or
overflowing. Layout can also adapt to the space it has. This works the same
on every GUI host and changes nothing for a host that never asks for it.

## Decision: scale stays in cells

Layout remains integer cells. A larger font means bigger cells and therefore
fewer of them; the window's cell grid shrinks, and every existing layout rule,
golden, and backend keeps working unchanged. This is how the web host already
behaves under browser zoom.

Sub-cell units and platform-measured frames are track 3's
`AppKitLayoutMetrics`, not this track. Mixing the two here would put a
second unit system into the cell path, which ADR 0017 keeps permanent and
cell-based.

## 1. Apple host (`Sources/GamaAppleUI/GamaHostView.swift`)

**Text size is a property.** `GamaHostView` gains
`public var fontPointSize: CGFloat` (default 14, clamped to 6...72). Setting
it:

1. Looks up the shared font for that size (below).
2. Re-measures `cellSize` with the existing "M" probe.
3. Clears the styled-font cache, since its fonts are keyed to the old size.
4. Posts a `.resize(gridSize())` and pumps one frame, exactly like
   `layout()` does today.
5. Invalidates the accessibility snapshot, whose rectangles use `cellSize`.

Setting the same value again is a no-op.

**One shared font per size.** Today's single static `baseFont` exists because
constructing fonts per host failed under CoreText pressure (the comment above
it records this). That constraint stays: the base font becomes a `@MainActor`
static cache keyed by point size, so every host at a given size shares one
immutable font. The cache is bounded by the clamp range and holds a handful of
entries in practice. `baseFontIdentifier` keeps its regression test meaning:
two hosts at the same size share one font.

**Dynamic Type (UIKit: iOS, iPadOS, tvOS, visionOS).** A new
`public var followsDynamicType: Bool` (default `false`, so current behavior
and every existing test hold). When `true`, the host computes
`UIFontMetrics.default.scaledValue(for: basePointSize)` and applies it through
`fontPointSize`. It recomputes when `preferredContentSizeCategory` changes,
observed through `registerForTraitChanges`. That API is available at the
package's minimums (iOS 17, tvOS 17, visionOS 1), so the deprecated
`traitCollectionDidChange` is not used.

**macOS text size.** macOS has no Dynamic Type for arbitrary views. The shell
(`Sources/GamaAppleShell`) adds View menu items Bigger (Command-+), Smaller
(Command--) and Actual Size (Command-0), stepping `fontPointSize` by 1 pt on
the key window's host view. The step and bounds are constants in the shell,
not the host.

**Backing scale.** Cell size is in points, so a move between displays with
different backing scales changes no layout. The host overrides
`viewDidChangeBackingProperties` (AppKit) and reacts to `displayScale` trait
changes (UIKit) only to request a redraw, so glyphs re-rasterize crisply.

## 2. Web host (`WebHost/`)

The grid font size becomes a CSS custom property, `--gama-font-size`
(default `14px`). `gama.js` exposes `setFontSize(px)`, which sets the
property, re-runs `cellMetrics()`, and calls `notifyResize()`, the same path
`document.fonts.ready` already uses. The demo page adds A-/A/A+ buttons.
Browser zoom keeps working as it does today. The Swift side
(`Sources/GamaWASM`) is unchanged; resize already arrives through
`gama_web_v2_resize`, so no export tier changes.

## 3. Android example (`Examples/Android`)

`MainActivity.kt` hardcodes `textSize = 24f` in pixels. It changes to
`TypedValue.applyDimension(COMPLEX_UNIT_SP, 14f, displayMetrics)`, so text
follows the system font scale and screen density, and it re-derives the cell
size and calls the existing embed resize on configuration change.

## 4. Terminal and Embed

The terminal owns its font; nothing changes there. Embed consumers own
pixels; the C ABI stays cell-based and `docs/backends/CEmbed.md` gains one
paragraph saying that scaling means resizing in cells.

## 5. Responsive layout (`Sources/GamaCore`)

Two portable, stdlib-only additions, both decided at build time from
`surfaceSize`, which is set before the build:

- **`EnvironmentValues.widthClass`**: `compact`, `regular` or `wide`, derived
  from `surfaceSize.width` with thresholds of fewer than 60 columns and 120 or
  more. The thresholds are public constants. It is read like any other
  environment value.
- **`ViewThatFits`**: takes an ordered list of candidate views, measures each
  with `LayoutEngine.measure` against the proposed size, and renders the first
  that fits, falling back to the last. It is a primitive (`Body = Never_`), the
  same shape the dock spec's `DockContainer` uses, and it adds no `RenderNode`
  case. Its limit is the same as `surfaceSize`'s: it fits the surface or the
  size it is proposed, not a frame solved later, and its documentation says
  so.

Both compile under `check-embedded.sh` and add no imports to a portable
target.

## Testing

Swift Testing only.

- **`AppleHostFontScaleTests`**:
  - Setting `fontPointSize` changes `cellSize` and `gridSize` and emits one
    resize.
  - The same value is a no-op.
  - Two hosts at one size share a font identifier.
  - The styled cache is cleared.
  - Accessibility rectangles use the new cell size.
  - Clamping at both ends.
  - With `followsDynamicType` on UIKit, a content-size-category trait change
    applies the scaled size. This runs as a compile-only check where no
    simulator runs in the gate.
- **`ResponsiveLayoutTests`**:
  - `widthClass` at each threshold edge.
  - `ViewThatFits` picks the first candidate that fits, falls back to the
    last, and yields `CellSerializer` goldens at 120x40, 80x24 and 40x20.
- **Shell:** the menu actions step the key window's size, as a unit test on
  the shell's action routing.
- **Web:** the browser smoke calls `setFontSize` and asserts a resize with a
  smaller grid.
- **Android:** covered by `check-android.sh` building the example; no new
  runtime proof is claimed.
- The Embedded size baseline (`scripts/embedded-size-baseline.txt`) is
  re-measured only if the GamaCore additions move the artifact outside its
  band. That is a deliberate re-measure, never a tolerance widening.

## Phases

One PR per phase, each gated by `scripts/check-apple.sh` then
`scripts/check.sh`, plus `GamaStudio/tools/check.sh` after phase 1:

1. Apple host `fontPointSize`, font cache, Dynamic Type, backing scale.
2. Shell zoom menu.
3. Web `setFontSize` and the Android density fix.
4. `widthClass` and `ViewThatFits`.

Phase 4 touches only GamaCore and can run in parallel with phases 1-3.

## Out of scope

Point-based layout (track 3), per-view font sizes, a theme or type-scale
system, and scaling inside native regions (the app's own view scales itself).
