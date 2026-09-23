# 0017 — Native presentation: a GUI host may present Gama views as platform controls

Status: Proposed (awaiting owner review). Supersedes the widget clause of
[0001](0001-own-the-rendering.md) and the "What 0001 still forbids" section of
[0016](0016-native-regions-narrow-own-the-rendering.md). 0001's shared IR and
shared layout stand; 0016's regions stand.

Design: [`2026-09-23-native-presentation-design.md`](../superpowers/specs/2026-09-23-native-presentation-design.md).

## Context

[0001](0001-own-the-rendering.md) made Gama own rendering end to end: one
`RenderNode` IR, one `LayoutEngine`, one `CellPainter`/`DrawList`, and
backends that only translate events in and present frames out. On a GUI host
that produces a monospaced cell grid drawn by CoreGraphics. It cannot look or
behave like the platform: no proportional text, no native buttons, fields,
IME, focus rings, or accessibility roles, and every one of those has to be
rebuilt from the IR ([0001](0001-own-the-rendering.md), Consequences).

The owner's goal for Gama apps, starting with the ABI operator app, is that
they blend in on macOS, iOS, Android, and Windows with real platform
controls, while panels, docking, and dragging behave identically everywhere.
The options were: keep cells and adopt platform conventions only; keep cells
and fill more of the window through native regions; or present the IR
through platform controls. The owner chose the last, with Gama keeping
ownership of layout (points, platform-measured).

## Decision

**A GUI host may present the laid-out IR as a tree of platform controls
instead of painting cells.** The following rules bind any implementation:

1. **One IR, one layout, one focus model.** Views still compile to
   `RenderNode`; `LayoutEngine` still computes every frame; `FrameHost` still
   owns identity, actions, focus order, and state. A native host places
   controls at frames Gama computed. It never lets the platform decide
   layout, so panel, split, and drag behavior cannot fork per platform.
2. **The platform measures, Gama decides.** Text and control intrinsic sizes
   come from the host through a portable `LayoutMetrics` value (a struct of closures). The core
   stays stdlib-only, integer, and Embedded-compilable; a native host's
   layout unit is one point.
3. **Authored lengths keep their meaning.** Spacing, padding, fixed frames,
   and `surfaceSize` stay in cells in the public API. A native host converts
   them with its cell size, so no existing app changes meaning.
4. **Control semantics travel in a side table, not the IR.** Controls
   register a portable `ControlDescriptor` through `BuildContext`, the same
   pattern as actions and native regions. `RenderNode`, the MLIR dialect,
   and the DrawList wire format ([0005](0005-drawlist-wire-format.md)) are
   unchanged.
5. **The cell path is permanent.** TUI, WASM, Embed, MLIR, and any host that
   does not opt in keep `CellPainter`. Every view must have a cell rendering;
   a native presentation is an alternative, never a replacement.
6. **Opting in is per host and explicit.** Native presentation is a separate
   host type. The existing cell `GamaHostView` keeps its behavior.
7. **No capability without evidence.** `docs/Capabilities.md` gains a row per
   platform only at the layer its evidence supports.

## Consequences

- Semantics are shared, but pixels and in-control interaction (text editing,
  IME, focus rings, accessibility roles) are the platform's on a native
  host. That fork is now intended rather than forbidden.
- Every new portable control needs a descriptor and a mapping on each native
  host, plus its cell rendering. Controls without a mapping present as a
  generic focusable container that forwards keys to `FrameHost`.
- Hosts on iOS, Android, and Windows follow the same contract in later
  sub-projects. Windows stays blocked on the toolchain
  ([0002](0002-toolchain-pinning.md)) unless the owner accepts a 6.4.x GUI
  exception.
- **Reviewing a future change.** A change that lets the platform lay out
  Gama views, adds platform imports to the portable targets, changes the
  meaning of authored cell lengths, or removes a view's cell rendering
  violates this record.
