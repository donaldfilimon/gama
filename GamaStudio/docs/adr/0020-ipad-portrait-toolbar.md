# ADR 0020: iPad portrait toolbar fits

Status: Accepted (2026-09-23)

## Context

ADR 0018 recorded, but did not fix, that in iPad portrait the regular
layout's single-row toolbar runs past the screen edge. Measured on the iPad
Pro 11-inch (M5) simulator, portrait, 834 pt wide, regular layout (the
touch host supplies `DocumentActions`, so the file buttons are present):
the toolbar row painted "Open  Save  Save As  Add Box  Add Sphere  Add Cone
Add Light  Add Camera  Duplicat" and was cut at the screen edge. Duplicate's
tail, Delete, Undo, Redo, Frame, and Graph were unreachable. On the iPhone
17 (402 pt wide) the compact layout (`StudioRootView.compactWidth`, 86
columns) is used instead and fits.

`GamaHostView` measures its monospaced cell size from
`NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)`'s "M" glyph,
ceiling the result (`Sources/GamaAppleUI/GamaHostView.swift`). Running that
exact measurement on this machine gives a 9.0 pt cell width. Dividing the
two device widths by it: 834 / 9.0 ≈ 92.67, floored to **92** columns for
the iPad, and 402 / 9.0 ≈ 44.67, floored to **44** for the iPhone. 92 is
above `compactWidth` (86), so the regular layout is the one in play, and 44
is well below it, matching the two observed layouts. The cutoff position
also lines up: the combined width of the eight buttons up through "Add
Camera" (Open, Save, Save As, then the five Add buttons) is 82 columns, and
the cut falls partway into the following "Duplicate" button, which is where
a toolbar row about 92-93 columns wide would cut it.

The regular toolbar's full single-row width, summing each `Button`'s
painted `" <title> "` (two columns of padding around the title) plus one
`HStack(spacing: 1)` gap before every button but the first, is 133 columns
with the file buttons (touch hosts) and 109 without (macOS, which uses its
File menu instead, per ADR 0009). Both exceed 92.

## Decision

1. **`StudioRootView.regular(width:)`** replaces the fixed `regular`
   computed property. It measures whether the single-row `toolbar` fits at
   the current surface width (`regularToolbarFits(width:)`, comparing the
   summed label lengths plus padding and gaps against `width`) and, when it
   does not, renders `toolbarForRegularLayout(width:)`'s wrapped form
   instead: a `VStack` of one row per button group (file, creation,
   editing), the same shape `compactToolbar` already uses below
   `compactWidth`, but keeping the regular layout's full (non-abbreviated)
   labels rather than compact's short ones, since the regular layout only
   ever appears at widths of 86 columns or more.
2. **No new button-building code.** The wrapped form calls
   `fileButtons(_:)`, `creationButtons(short: false)`, and
   `editingButtons(short: false)` verbatim, the exact closures and
   `actionIdentity`s the single-row toolbar already uses, so there is
   exactly one place each action is wired up, regardless of which shape the
   toolbar renders in.
3. **Wrapping into three fixed groups is sufficient, not just convenient.**
   Each group's own row width is small enough to always fit once the width
   has already cleared `compactWidth`: the creation row (Add Box … Add
   Camera) is 58 columns, editing (Duplicate … Graph/Inspector) is 50, and
   file (Open, Save, Save As) is 23; each under `compactWidth` (86), so a
   width of 86 or more that still cannot hold the single combined row of
   133/109 can always hold each group on its own row. A more general
   per-button wrap was not needed to satisfy requirement 1.
4. **The compact layout (below `compactWidth`) is unchanged.**

## Consequences

- Every toolbar action (the same `ActionID`s, same order) is reachable at
  any surface width, matching requirement 1. `IPadToolbarWrapTests`
  (`Tests/GamaStudioEditorTests/IPadToolbarWrapTests.swift`) paints
  `StudioApp` at the derived 92-column iPad-portrait width, with and
  without `DocumentActions`, and at a 200-column wide width, and requires
  every toolbar label to appear un-clipped (as a whole word, not a
  substring cut mid-label) in each case; it fails on the pre-fix code at
  92 columns (both with and without file buttons) and passes at 200
  columns even before the fix, since the single row already fits there.
- The 92/44-column figures are a measurement on this machine's system
  font, not a value read from the simulator itself; a different display
  scale, font, or platform could shift the constant. The test's derivation
  is recorded in the file's own header so a future re-measurement can
  correct it without re-deriving from scratch.
- The wrap threshold (`regularToolbarFits`) is computed from a second copy
  of the button labels (`creationLabelsRegular`, `editingLabelsRegular`,
  `fileLabelsRegular`) rather than measuring the rendered layout, so a
  future label change must update both the `Button` call and this list or
  the fits-check will silently drift from what is actually painted.
  `IPadToolbarWrapTests.toolbarWrapThresholdMatchesTheActuallyRenderedWidth`
  is a black-box test for exactly that drift: it measures the toolbar's
  actual painted width at a wide surface, then requires the toolbar to
  still be one row right at the boundary that width implies and wrapped
  (labels still fully visible) one column narrower, with and without file
  buttons. Deliberately shortening one label copy by one character
  (`"Add Camera"` → `"Add Camer"` in `creationLabelsRegular`) makes this
  test fail while the other three `IPadToolbarWrapTests` still pass,
  confirming it catches the drift the other tests do not. The 133/109/58
  column figures above were verified against this test's own measurement
  (`row 0`'s painted width plus one, for the last button's trimmed trailing
  pad space), not by hand arithmetic alone; an earlier draft of this ADR
  had miscounted "Add Camera" as 11 characters instead of 10 and reported
  134/110/59.
- Verified by hand on 2026-09-23 on the iPad Pro 11-inch (M5) simulator in
  portrait: the toolbar wrapped into three rows with every button on screen,
  and tapping Frame, previously off-screen, logged "· framed the scene"
  (ADR 0018).
- Not built: a fully generic per-button wrap. The three-group split is
  provably sufficient for the current label set (see Decision 3) but would
  need revisiting if a future toolbar group's own row width approached or
  exceeded `compactWidth`.
