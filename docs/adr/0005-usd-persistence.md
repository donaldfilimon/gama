# ADR 0005: Documents persist as USDA through Gama's own codec

Status: Accepted (2026-09-23)

## Context

Through ADR 0004, Gama Studio could author a `SceneDocument` but not keep
one: quitting lost everything. The spec names USD as the interchange format,
and `AGENTS.md` listed "save/load, implemented against the real SDK APIs" as
the next phase after selection highlighting. Donald asked for USD save and
load on 2026-09-23.

Two SDK routes were measured and rejected for the document itself:

- RealityKit's `Entity.write(to:)` exports the *projection*, not the
  document. It has no place for entity identifiers, primitive kind, the
  editor's visibility and lock state, or cameras (a document camera is never
  a RealityKit camera, ADR 0004). It also cannot read anything back.
- ModelIO reads and writes USD meshes, but it would give back a mesh
  hierarchy rather than Gama's components, and it cannot be used from a
  standard-library-only target.

Apple USD Tools 0.25.11 ship in `/usr/bin` (`usdcat`, `usdchecker`,
`usdzip`). They validate files but are not a linkable API.

## Decision

1. **A new `GamaUSD` target writes and reads USDA text, standard library
   only.** `usdaString(from:)` and `sceneDocument(fromUSDA:)` operate on
   `String`. `tools/check.sh` applies the same import ban to it as to
   `GamaAuthoring`. File access lives in `StudioDocumentIO`
   (`GamaStudioEditor`), the one place Foundation touches the disk.
2. **The file is real USD first.**
   - Entities become prims, children nested in authored order.
   - Meshes become UsdGeom gprims at the unit sizes `PrimitiveMeshes`
     projects: `Cube` size 1, `Sphere` radius 0.5, `Cylinder`/`Cone` height 1
     radius 0.5, and `Plane` 1×1 on Y.
   - Transforms become `xformOp:translate`, `orient` (real part first), and
     `scale`.
   - Materials become `UsdPreviewSurface` shaders in one `Looks` scope,
     bound with `material:binding` and `MaterialBindingAPI`.
   - Lights become `DistantLight`, or `SphereLight` with `treatAsPoint`
     (plus `ShapingAPI` for spots).
   - Cameras become `Camera` with `focalLength` over a 24 mm vertical
     aperture and `clippingRange`.
   - Hidden entities become `visibility = "invisible"`.
   - `usdchecker` accepts the output. The gate checks this on every run.
3. **`gama:` attributes are authoritative on read.** The file carries:
   - `gama:id`, and `gama:name` holding the exact name (prim names are
     sanitized to USD identifiers, and a collision or reserved name gets
     `_<id>`);
   - `gama:intensity`, `gama:attenuationRadius`, `gama:innerAngle`,
     `gama:outerAngle`, and `gama:fieldOfView`;
   - `gama:visible` and `gama:locked`;
   - the layer's `gama:formatVersion` and `gama:nextEntityID`.

   UsdLux intensity has its own photometric model, so `inputs:intensity`
   is written as a preview approximation (lux or lumens ÷ 1000). Only
   `gama:intensity` round-trips. Numbers use `Float.description`, the
   shortest text that reads back bit-identically.
4. **An entity with more than one prim-typed component** (mesh, light,
   camera) becomes an `Xform` holding child prims named `GamaMesh`,
   `GamaLight`, and `GamaCamera`, each marked `gama:component = 1`. The
   reader folds them back into the entity. One such component stays inline
   on the entity prim.
5. **The round trip is exact.** Reading what was written gives back an
   equal `SceneDocument`: identifiers, names, component values, sibling
   order, and the identifier allocator. `SceneDocument` gains
   `init(restoring:roots:nextEntityID:)` for this. It builds a whole value
   and runs `validate()`. Mutation stays command-only.
6. **The reader refuses what it does not understand.** The following raise
   `USDError`, which names the line it stopped at:
   - unknown prim types;
   - time samples;
   - variant sets;
   - a missing or different `gama:formatVersion`;
   - a missing `gama:id` or a duplicated one;
   - a dangling material binding.

   A file that parses but describes an invalid document is refused as
   `.invalid`. Properties Gama does not read, such as `extent`, are
   ignored. The reader accepts the same content after `usdcat` reformats
   it: reordered attributes, reflowed metadata, and shortened floats.
7. **Opening a file replaces the document and is not undoable.**
   `StudioModel.replaceDocument` does all of the following:
   - starts a fresh `EditorSession`, which clears undo, redo, and
     selection;
   - clears `lastError`;
   - rebuilds the bridge;
   - treats the new content as saved;
   - fires `onDocumentChange`.

   `hasUnsavedChanges` compares content with what was last opened or
   saved, so undoing back to it reads as clean.
8. **UI.** The File menu offers Open… ⌘O, Save ⌘S, and Save As… ⇧⌘S
   through `NSOpenPanel` and `NSSavePanel`. It asks Save / Don't Save /
   Cancel before Open or Quit discards unsaved changes, and reports every
   failure in an alert. The window title, proxy icon, and edited dot
   follow the current file. There is no toolbar button: saving is not a
   scene edit. For scripts and the gate, `gama-studio --open <usda>` starts
   from a file, and `--export <usda>` writes and exits without building
   any UI.

## Consequences

- The gate's `usd` stage runs these steps:
  1. export the sample;
  2. `usdchecker` must report `Success!`;
  3. `usdcat` the export;
  4. read that back and re-export;
  5. the two exports must be byte-identical. Because the writer is
     deterministic, byte equality means the reformatted file described the
     same document. The stage fails closed when the tools are missing.
- `GamaUSDTests` pins exact round trips over every component kind and
  primitive, awkward names, combined components, and the empty document.
  It also pins a golden file (`GAMA_UPDATE_GOLDEN=1` regenerates it), a
  checked-in `usdcat` reformatting of it, and every refusal with its line.
  Mutating the orient component order or dropping the component fold fails
  several of those tests (measured 2026-09-23).
- A Gama-written file opens in any USD viewer with the right shapes,
  hierarchy, colors, and camera. Light brightness there is approximate.
- Proposed, not built:
  - `.usdz` packaging;
  - reading USD that Gama did not write (arbitrary prims, meshes,
    references, and layers need a real USD parser or the C++ SDK);
  - autosave and a recent-files menu.
