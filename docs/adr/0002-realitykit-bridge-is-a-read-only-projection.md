# ADR 0002: The RealityKit bridge is a read-only, incremental projection

Status: Accepted (2026-09-23)

## Context

Phase 1 of the spec (§10, §61) projects the authoring document into
RealityKit. The spec asks for three things: the bridge updates only the
affected runtime objects, it never rebuilds the scene for a small change, and
RealityKit is never the canonical database (invariant 1). ADR 0001 already
fixed the feed contract: `SceneChange` names what changed, and the consumer
reads the current value from the document.

Measured facts that shaped this (MacOSX27.2 SDK, RealityFoundation interface,
and runtime probes under `swift test`):

- `Entity`, `ChildCollection`, and every `MeshResource.generate*` function are
  `@MainActor`.
- `generateCone` and `generateCylinder` require macOS 15, iOS 18, tvOS 26, and
  visionOS 1.
- Entities, meshes, and `PhysicallyBasedMaterial` can be created headless in the
  SwiftPM test runner, with no window, view, or GPU context needed.
- **`ChildCollection` does not preserve sibling order on removal.** Removing the
  first of `[a, b, c]` left `[c, b]`, because the last child moved into the
  vacated slot. Order cannot be maintained by per-operation index arithmetic.

## Decision

1. **`GamaReality` is a separate Apple-only target.** It wraps every file in
   `#if canImport(RealityKit)`, and `GamaAuthoring` stays import-free.
   `RealityBridge` is a `@MainActor final class`. It owns a `root` entity and
   no view.
2. **Read-only.** The bridge reads `SceneDocument` and never writes it. Nothing
   reads authored state back out of RealityKit. Picking goes through
   `id(for:)` to an `EntityID`.
3. **Incremental application.**
   - `apply(_:from:)` touches only the entities the changes name, and reads
     values from the document after the commit.
   - A change naming an entity the document no longer holds is skipped, because
     a later change in the same batch removed it. That makes any drained batch
     safe, however much it churns.
   - `rebuild(from:)` exists only for opening a document and as the reference
     the tests compare against.
4. **Sibling order is settled once per pass.** Each pass records the containers
   whose children changed. At the end of `apply` (and `rebuild`), each recorded
   container is compared with the document and re-sequenced only if it differs.
   Containers that weren't touched are never visited.
5. **Unit-size meshes, scale from the transform.** Each `Primitive` maps to one
   cached unit-size `MeshResource`: a 1 m box, radius-0.5 sphere,
   height-1/radius-0.5 cylinder and cone, and a 1 × 1 plane. Size is authored
   as transform scale. The `switch` is exhaustive, so a new primitive can't
   ship unmapped.
6. **The platform floor rises to macOS 15, iOS 18, tvOS 26 (visionOS 1).**
   Substituting a box for a cone or cylinder on older systems would be a silent
   misprojection. Gama itself requires macOS 14, and a consumer may require
   more.
7. **Defaults for absent components.** No transform means identity. A mesh
   without a material uses the default `Material()`. No mesh means no
   `ModelComponent`. No visibility means enabled.
8. **Base colors are linear sRGB end to end.** The authored `baseColor` is
   linear, matching USD material colors. Each channel is encoded with the
   exact sRGB transfer function, and the tint is then built with the sRGB
   initializer. Passing linear values straight through would declare them
   gamma-encoded, and an authored 0.5 would render at 0.214 (measured by
   mutation). A linear-space `CGColor` would avoid the encoding, but its
   initializer takes a raw pointer, which strict memory safety flags as
   `unsafe`. A mid-grey test pins the behavior, since pure primaries look the
   same in both spaces.
9. **Collision shapes are projected with the mesh, for picking.** Setting a
   `ModelComponent` also sets a matching `CollisionComponent`, one shape per
   cached unit primitive; removing the mesh removes both. The plane uses a
   thin box (it has no volume of its own), and the cylinder and cone use the
   convex hull of the cached mesh rather than an approximation.

## Consequences

- The correctness test is convergence: over seeded random command sequences,
  including transactions, undo, redo, and batches drained every 1, 7, or 13
  steps, the incremental tree must equal a fresh rebuild after every drain.
  Removing reparent handling fails every run.
- Re-sequencing a changed container is O(children) and happens only when order
  actually differs.
- Only macOS is built and tested here. iOS, tvOS, and visionOS builds of
  `GamaReality` are unmeasured.
- Camera, lights, selection highlighting, and a viewport are not part of this
  decision. The document has no camera or light components yet.
