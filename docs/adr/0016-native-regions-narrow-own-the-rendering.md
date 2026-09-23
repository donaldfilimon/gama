# 0016 — Native regions: an application-owned view may fill a region Gama lays out

Status: Accepted. Narrows the consequence of [0001](0001-own-the-rendering.md);
0001's decision stands.

Nothing in this record is built. It settles the policy question the
[native view embedding draft](../superpowers/specs/drafts/2026-09-23-native-view-embedding-draft.md)
raised as its sixth open question. The draft's other open questions belong to
the implementation design and are not decided here.

## Context

[0001](0001-own-the-rendering.md) made Gama own rendering end to end. Views
compile to one `RenderNode` IR, one `LayoutEngine` and one
`CellPainter`/`DrawList` layer are shared by every backend, and backends only
translate events in and present frames out. Its consequence, that "visual and
interaction semantics cannot fork per platform", has been read as "Gama does
not wrap platform widgets", and that reading has served the project well.

The first external consumer, a 3D authoring app, needs a RealityKit viewport
inside a window whose panels are Gama views. The pixels of a 3D viewport
cannot come from a cell painter. The options were to:
- keep Gama pure and build the application's shell natively around a Gama
  host, or
- let Gama reserve a region that an application-owned native view fills.

The owner chose the second, on the condition that the exception is explicit
and bounded rather than a general widget-wrapping layer.

## Decision

**Gama may lay out a *native region*: a node in the shared IR whose pixels and
in-region events, on a backend that opts in, come from a view the application
owns.** The following rules bind any implementation:

1. **The region is ordinary IR.** It has an identity, a laid-out frame, a flex
   behavior, and a place in focus order. It is hit-tested up to its boundary
   by `FrameHost` like any other node. Layout, focus order, and region
   identity never fork per backend.
2. **A fallback is mandatory and portable.** Every region carries fallback
   content that `CellPainter` paints. A backend that doesn't opt in, and an
   opting-in host with nothing attached, shows the fallback. A native region
   therefore never makes an app blank or broken on the TUI, WASM, or Embed
   backends.
3. **Only presentation hosts opt in, and only inside the region.** Filling a
   region is a host capability. Today that is the Apple host
   (`GamaAppleUI`), the only backend that already owns platform views. The
   filled view's pixels, the events it receives inside its frame, and its own
   accessibility tree are **outside Gama's guarantees**, the same boundary
   shape as the `gama_embed_v1_*` C ABI: one explicit escape hatch at the
   edge.
4. **The application owns the native view.** Gama never creates, configures,
   or retains a platform view on its own initiative. It positions, shows, and
   hides what the application attaches, and it hands over first responder
   when its focus lands on the region.
5. **The portable core stays portable.** Region identity is a plain value.
   GamaCore, GamaPlugin, GamaDraw, GamaEmbed, and GamaMLIR gain no platform
   imports, and `scripts/portable-global-state.py` and the boundary gate are
   unchanged.
6. **The DrawList wire format doesn't carry regions.** Regions travel to a
   host beside the laid-out frame, so [0005](0005-drawlist-wire-format.md)
   version 1 is unchanged. Publishing regions through the Embed C ABI or the
   WASM exports would be a public-ABI change and needs its own record.
7. **The name is "native region".** "Surface" already means a presentation
   host ([0011](0011-reactive-state-is-per-surface.md), `SurfaceMode`,
   `surfaceSize`) and "slot" means `PluginSlot`.

**What 0001 still forbids.** Gama doesn't wrap platform widgets as framework
controls. `Button`, `TextField`, `Toggle`, and every other Gama view stay
built from the shared IR on every backend. A native region is a hole the
application fills, not a way for the framework to borrow a platform control.
The other drafts that rely on 0001 (native desktop backends, GPU compositor)
are unaffected.

## Consequences

- **0001's consequence is narrowed.** Semantics cannot fork per platform
  *outside native regions*. Inside a filled region on an opting-in host, the
  application's view defines what is seen and done. This record is the only
  licence for that.
- **The cost is accepted.** The implementation design must still settle the
  draft's remaining open questions: node shape versus a side table, Tab
  traversal out of a native view, overlays above a region, sub-cell
  placement, other backends publishing regions, and AppKit/UIKit scope.
  Whatever it picks, it must not break rules 1 to 7.
- **No capability is claimed.** `docs/Capabilities.md` gains a native-region
  row only when an implementation has evidence, at the layer that evidence
  supports. Until then the status of native regions is "not built".
- **Reviewing a future change.** A change that makes a Gama view render
  through a platform control, fills a region without a fallback, or moves
  region data into the portable targets through a platform import violates
  this record and 0001 together.
