# ADR 0001: The authoring core is a value document edited only by invertible commands

Status: Accepted (2026-09-23)

## Context

`docs/spec/2026-09-23-unified-usd-realitykit-spec.md` defines Gama Studio as a
document-centric 3D authoring platform. The document and command model sit at
the center, USD is the save and interchange boundary, and RealityKit is a
rendering projection (spec §1, §64). Its Phase 0 (§61) asks for a reliable
authoring model before any rendering.

The spec sketches types but leaves their mechanics open, and some of its
sketches conflict with determinism and portability. It also names the core
module `GamaCore`, which collides with the `GamaCore` module of the gama
framework this app will depend on for its editor UI.

## Decision

1. **Module name `GamaAuthoring`, standard library only.** It imports nothing
   (no Foundation, simd, RealityKit, SwiftUI, AppKit, UIKit, Darwin, Glibc,
   Dispatch, or Combine), and `tools/check.sh` enforces this. The core stays as
   portable as gama's own portable targets, and the spec's invariant 10 (the
   runtime projection can be replaced without destroying the authoring model)
   holds by construction. `SIMD3`, `SIMD4`, and `Codable` are standard library.
   `simd_quatf` is not, so rotation is an own `Rotation` quaternion that a
   runtime bridge converts at the boundary.
2. **`EntityID` is a document-allocated `UInt64`, not a `UUID`.** Identifiers
   come from a monotonic counter in the document, are never reused (not even
   after undo), and are deterministic, so tests, diffs, and replays are
   reproducible without Foundation. Collaboration (spec §35), which needs
   identifiers unique across devices, will need a namespaced scheme. That is
   out of scope here.
3. **`SceneDocument` is a value type.** `EditorSession` applies a command or a
   whole transaction to a copy, runs `SceneDocument.validate()` on the result,
   and commits only if both succeed. Rollback (spec §12) is therefore exact and
   free: a refused edit changes nothing, not the document, history, revision,
   selection, or change feed.
4. **Commands are synchronous and return their exact inverse.** The session
   records the inverse for undo. Redo applies the inverse of the inverse, never
   the original command, so a redone creation keeps its original identifier and
   later commands that reference it still resolve. The spec's `async` command
   signature (§11) is not adopted: asynchrony belongs to the work that
   *produces* commands (import, graph evaluation, AI planning), not to the
   mutation itself.
5. **The change feed names what changed, not the new value.** `SceneChange`
   entries carry identifiers and component kinds, and a projection reads the
   current value from the document. A projection that applies the feed in order
   converges on the document and updates only affected objects (spec §10).
6. **Selection is editor state, not history.** Selection changes are not
   undoable, the session prunes the selection when entities disappear, and undo
   does not restore a pruned selection.

## Consequences

- Undo correctness is testable per command: execute, undo, and compare content;
  redo, and compare again (`CommandRoundTripTests`).
- `SceneDocument.hasSameContent(as:)` excludes the identifier allocator, because
  the allocator advancing across undo is intended.
- Copying the document per step is O(n) in entity count. That is acceptable for
  Phase 0. If profiling shows it matters, persistent structures or per-command
  in-place application with validated inverses can replace it without changing
  the command API.
- The spec's `GamaCore` naming in its module diagrams maps to `GamaAuthoring`
  here.
