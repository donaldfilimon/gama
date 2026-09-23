# ADR 0004: Cameras and lights are authored components

Status: Accepted (2026-09-23)

## Context

ADR 0003 gave Gama Studio a document, an incremental RealityKit bridge, and
an editor UI, but cameras and lights were both editor-only: `StudioModel`
carried no camera or light state, and `ViewportController` drove a fixed
`PerspectiveCamera` and a fixed `DirectionalLight` that had no relationship
to the document ("Camera components in the document remain unbuilt", ADR
0003 Consequences; `AGENTS.md` "Not built" item 1). Donald asked for both as
document state, with rules set 2026-09-23: a camera is authored but never
takes over the viewport; lights actually light the scene; the sample scene
should ship with a "Key Light" and a "Camera".

## Decision

1. **`Light` and `CameraSettings` are ordinary `GamaAuthoring` components,
   like transform, mesh, material, and visibility.** `Component` gains
   `.light(Light)` and `.camera(CameraSettings)`; `ComponentKind` gains
   `.light` and `.camera` after `.visibility`. Both types are
   `Hashable, Codable, Sendable`, standard-library only (`Lighting.swift`,
   beside the other `GamaAuthoring` component files), and each has a
   `validate() throws(AuthoringError)`. They are set, changed, and removed
   through the same `SetComponent`/`RemoveComponent` commands as every other
   component, so they get undo, transactions, the change feed, and JSON
   `Codable` round-tripping for free — no light- or camera-specific command
   type exists, and none is needed (ADR 0001). A refused `SetComponent` (an
   invalid light or camera) changes nothing, per ADR 0001's rollback
   guarantee.
2. **`Light` holds a kind, a linear color, and an intensity in the runtime
   projection's native unit.** `LightKind` is `.directional`,
   `.point(attenuationRadius:)`, or `.spot(innerAngleDegrees:outerAngleDegrees:attenuationRadius:)`,
   with `0 < inner <= outer < 180` and a positive, finite attenuation
   radius. `color` is linear RGB, each channel in `0...1` (matching ADR
   0002 item 8's material colors). `intensity` must be finite and
   non-negative, but the two light families measure it in **different
   RealityKit units**: `DirectionalLightComponent`'s intensity is lux
   (illuminance — a directional light has no distance falloff, so
   RealityKit expresses it as how bright a surface gets), while
   `PointLightComponent` and `SpotLightComponent`'s intensity is lumens
   (luminous flux, the light's own output, which then falls off with
   distance). `Light` does not encode the unit as a type distinction: it is
   one `Float` whose meaning depends on `kind`, and the UI labels it ("lx"
   vs. "lm" in `StudioApp.intensityUnit(_:)`). Consequently,
   `StudioModel.cycleLightKind()` **resets intensity whenever a cycle step
   crosses the lux/lumens boundary** (directional → point, and spot →
   directional), to each family's default (`Light.defaultDirectional`'s
   3000, or `Light.defaultPoint`'s 26963.76 — RealityKit's own
   `PointLightComponent` default), because carrying a raw number across
   would make the light roughly 9× too dim or too bright. A point-to-spot
   step keeps the intensity, since both families are lumens.
   `Light.defaultPoint`'s 10 m attenuation radius and its intensity are
   chosen to be visible a few meters away, not for physical accuracy.
3. **`CameraSettings` holds field of view, near, and far, and nothing
   about the viewport.** Field of view is `1...179` degrees, `near` is
   finite and positive, `far` is finite and greater than `near`; defaults
   are 60° / 0.01 / 1000, matching `ViewportController`'s previous fixed
   camera. **A document camera never becomes a RealityKit camera, in either
   direction.** `RealityBridge` never sets a `PerspectiveCameraComponent`
   for `.camera` (`RealityBridge.project(_:onto:)`), and the viewport's own
   `PerspectiveCamera` is never written back into the document — a camera
   entity's transform and `CameraSettings` are read only when "Look
   through" is pressed (decision 6). The viewport keeps exactly one active
   camera, always its own; a document can hold any number of camera
   entities and none of them is ever "the" camera.
4. **Lights are projected as real RealityKit light components; cameras are
   projected as a marker only.** `LightProjection.swift`'s
   `Light.project(_:onto:)` sets exactly one of `DirectionalLightComponent`,
   `PointLightComponent`, or `SpotLightComponent` on the entity, always
   removing the other two first, so a kind change or a removal never
   leaves a stale light behind (this refines ADR 0002 item 10, corrected
   below). The color follows ADR 0002 item 8: linear, sRGB-encoded with
   `Material.encodeSRGB`, then wrapped in a platform color. **All three
   light initializers take `NSColor` on macOS (`UIColor` elsewhere), not
   `CGColor`**: of the three, only `PointLightComponent` has a public
   `init(cgColor:intensity:attenuationRadius:)`; `DirectionalLightComponent`
   and `SpotLightComponent` have no public `CGColor`-taking initializer in
   the RealityFoundation SDK. Rather than mix `CGColor` for point lights and
   `NSColor`/`UIColor` for the other two, the bridge uses `NSColor`
   uniformly for all three (`PlatformColor.encoding(linear:)`), which also
   sidesteps `CGColor(colorSpace:components:)`'s raw-pointer initializer
   that strict memory safety would flag as `unsafe`. This corrects ADR
   0002 item 10's original wording, which described the SDK's `CGColor`
   surface less precisely.
5. **A camera or light entity gets one unmapped marker child, named
   `"GamaReality.marker"`, so it can be seen and picked** (ADR 0002 item 10,
   ADR 0003 decision 5). The marker carries an `UnlitMaterial` and a
   collision shape sized to its kind: a camera gets a 0.2 × 0.15 × 0.3
   dark-grey (linear 0.05) box; a light gets a radius-0.1 sphere in the
   light's own color, lifted so its brightest channel is at least 0.5 (a
   black or very dim light still shows a visible marker). **An entity with
   both a camera and a light gets the camera marker** (`Marker.init(_:)`
   checks `.camera` before `.light`); the entity keeps its
   `DirectionalLightComponent`/`PointLightComponent`/`SpotLightComponent`
   either way, only the marker's shape is affected. Markers are created,
   updated, and removed alongside the components that need them, are
   excluded from `RealityBridge.count` and `id(for:)`
   (`RealityBridge.project(_ marker:onto:)` only ever tracks them by node
   identity, never registers them in `identities`), and
   `ViewportController.pickedEntityID(for:in:)` resolves a hit on one by
   walking up to its parent, the owning entity.
   - **Markers inherit visibility, and this is RealityKit's own hierarchy
     behavior, not code the bridge writes.** `project(_ record:onto:)` sets
     `entity.isEnabled` from the owner's `Visibility` component; the marker
     node's own `isEnabled` is never touched. RealityKit composes
     `isEnabledInHierarchy` down the entity tree, so hiding the owner hides
     its marker for free.
   - **Markers scale with the owner's transform — an accepted limitation,
     not a feature.** The marker node's `RealityKit.Transform` is left at
     its default (identity); nothing counter-scales it against the owner's
     transform, so a light or camera entity scaled up or down (which is
     meaningless for either component but not rejected by
     `Transform.validate()`) renders a stretched marker rather than a
     fixed-size one. Fixing this would need an explicit inverse-scale on
     the marker, tracked as future work, not built here.
   - Re-sequencing a container after a sibling add, remove, or reorder
     (`resequenceTouchedContainers`) keeps unmapped children (markers)
     after the mapped ones and preserves them across the pass; adding or
     removing a marker itself marks its owner as touched, so its container
     is included in the next re-sequencing pass.
6. **The editor's own light is a fallback, on only when the document has no
   visible light of its own.** `ViewportController.editorLight` (a fixed
   `DirectionalLight`, unchanged in direction and intensity from before this
   ADR) is enabled exactly when
   `ViewportController.documentHasEnabledLight(_:)` is false: it walks every
   entity that carries a `.light` component and checks that the entity and
   every ancestor has `Visibility.visible` true (a missing `Visibility`
   counts as visible). **An entity with a light whose `intensity` is 0 still
   counts as "enabled" if it and its ancestors are visible** — the fallback
   turns off even though the scene goes dark, because the check is about
   whether the document is *managing* its own lighting, not about whether
   the result is bright enough. This is an accepted limitation, not a bug:
   distinguishing "authored but effectively off" from "not authored" would
   need a brightness threshold with no principled value. The check re-runs
   from `StudioModel.onDocumentChange`, which fires after every applied
   edit, undo, and redo, so adding, hiding, deleting, or undoing a light all
   flip the fallback correctly; it also runs once at `ViewportController`
   construction, so the sample scene's "Key Light" turns the fallback off
   immediately.
7. **"Look through" is editor state, not a document command.** Pressing it
   (`ViewportController.lookThrough(_:)`, reached from the inspector's
   "Look through" button via `ViewportActions.lookThrough`) sets the orbit
   camera's eye to the authored camera entity's world position, its target
   to that position plus the entity's world −Z direction times the
   *current* orbit distance (so zoom level carries over), and the viewport
   `PerspectiveCamera`'s field of view to the authored `CameraSettings`.
   None of this touches `SceneDocument`: it is not undoable, not part of
   the change feed, and not saved — exactly the same footing as the
   existing `OrbitCamera`/"Frame" behavior ADR 0003 decision established.
   Three consequences follow directly from reusing `OrbitCamera`:
   - **Orbiting after "Look through" does not move the authored camera.**
     The document is never written; only the editor's own camera state
     changes.
   - **Pitch is clamped to `OrbitCamera`'s existing ±85° limit**, so a
     camera authored to look more steeply up or down than that is shown
     clamped to 85°, not at its true angle.
   - **Roll is not reproduced.** `OrbitCamera` has no roll axis, so an
     authored camera rotated around its own view direction looks through
     as if it had none.
   - **Field of view is not restored by "Frame".** `lookThrough` sets the
     viewport camera's field of view from `CameraSettings`, but `Frame`
     (ADR 0003) only repositions the orbit target and distance; it never
     resets field of view. Looking through a camera and then pressing
     "Frame" keeps that camera's field of view — an accepted asymmetry
     between the two actions, documented rather than fixed, because
     "Frame" predates cameras and changing its contract is out of scope
     here.
8. **The picking-through-the-eye rule now has a concrete trigger.**
   `ViewportController.pick(at:)` already ignored hits at or below
   `insideHitDistance` (1e-4 m) because a shape containing the eye reports
   distance 0 for every point in the view (ADR 0003 decision 5's
   collision-based picking). Cameras and their markers make this common
   rather than theoretical: the sample scene's "Camera" starts exactly at
   the orbit eye's initial position, and `lookThrough(_:)` always moves the
   eye to sit inside whatever camera's marker was looked through. A click
   whose ray starts inside a shape — most often that camera's own marker,
   right after adding it or looking through it — ignores that shape and
   resolves to the nearest hit strictly farther than 1e-4 m instead.
9. **The sample scene gained a "Key Light" and a "Camera".**
   `StudioModel.sampleScene()` now creates them last, after the ground and
   three primitives, so the first four hierarchy rows are unchanged: a
   directional "Key Light" at intensity 3000 (matching the old fixed
   editor light's brightness) positioned at `(3, 6, 4)` and aimed at the
   origin, and a "Camera" with default `CameraSettings` at `(0, 3, 7)`,
   also aimed at the origin — the same point the viewport's orbit camera
   already starts from. Both rotations come from `Rotation.lookAt(_:from:up:)`
   (`LookAt.swift`), a small helper kept in `GamaStudioEditor` rather than
   `GamaAuthoring`, because it needs `simd` and `GamaAuthoring` stays
   standard-library only (ADR 0001 decision 1); it hands `GamaAuthoring` a
   plain `Rotation` value.
10. **macOS only.** `Light` and `CameraSettings` live in `GamaAuthoring`
    and are platform-free, but their projection
    (`LightProjection.swift`), their markers, and the UI that authors and
    displays them are gated the same way as everything else built on top
    of them: `GamaReality` on `canImport(RealityKit)`, `GamaStudioEditor`'s
    viewport and app on `canImport(AppKit) && canImport(RealityKit)` /
    `canImport(AppKit)`. iOS, tvOS, and visionOS hosting of any of this is
    unbuilt and unmeasured, the same caveat ADR 0002 and ADR 0003 already
    carry.

## Consequences

- **`AGENTS.md`'s "Not built" item 1 is retired for cameras and lights.**
  Its other half, selection highlighting, remains unbuilt and keeps its own
  item; nothing here adds it.
- **The gate's floor rises** with every new test in
  `Tests/GamaAuthoringTests/` (validation, round trips, `Codable`),
  `Tests/GamaRealityTests/LightProjectionTests.swift` and
  `RealityBridgeTests.swift` (mapping and convergence with lights, cameras,
  and markers in the mix), and
  `Tests/GamaStudioEditorTests/LightsAndCamerasTests.swift` (model actions,
  the fallback light, "Look through", and the inspector/toolbar additions).
- **A camera in the document is authored data with no forced relationship
  to what the user is currently looking at.** A scene can hold zero, one,
  or many cameras; none of them is privileged, and deleting or hiding the
  one just looked through does not move the viewport back. This is a
  deliberate consequence of decision 3 and 7, not an oversight: the
  viewport's camera is editor state, full stop.
- **Marker scale is a known rough edge** (decision 5): authoring a
  non-uniform or very large/small scale on a light or camera produces a
  visibly wrong-sized marker. Because scale is otherwise meaningless for
  both component kinds, this is judged low-severity and left for later
  rather than adding marker-specific transform logic now.
- **The fallback light's "enabled" check is coarser than "actually
  lighting anything"** (decision 6): a zero-intensity but visible light
  still turns the fallback off, so a document can end up genuinely dark
  with the fallback correctly deferring to authored state that isn't
  providing any. This matches the decision's own reasoning — it answers
  "is the document managing lighting," not "is the scene lit" — and is
  listed here as a known, accepted gap rather than a bug to fix silently
  later.
- **This ADR does not cover:** USD save/load of lights or cameras, a
  command console, a typed graph framework, non-macOS hosting, or
  selection highlighting. Those remain future ADRs (`AGENTS.md` "Not
  built").
