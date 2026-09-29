# Cameras and lights as authored components

## Context

Gama Studio's document holds transform, mesh, material and visibility components. The viewport has an editor-only orbit camera (`OrbitCamera`, ADR 0003) and a fixed editor light. Donald asked for camera and light components in the document. His decisions, 2026-09-23:
- **Cameras** are authored objects: field of view and near/far planes, placed by their transform. The viewport shows each one as a pickable marker and offers **Look through**, which snaps the editor's orbit camera to that camera's viewpoint and field of view. A document camera never becomes a RealityKit camera, so it can never take over the viewport.
- **Lights** (directional, point, spot) are projected into RealityKit and really light the scene. The editor's built-in light is a **fallback**: it is on only when the document has no visible light.
- **The sample scene** gains a directional "Key Light" that matches today's editor light, and a "Camera" at the current default viewpoint (0, 3, 7), looking at the origin.

The binding rules:
- `GamaAuthoring` stays standard-library-only, and the gate enforces it.
- Every edit is a `DocumentCommand` through `EditorSession`, and a refused edit changes nothing (ADR 0001).
- The bridge is a read-only, incremental projection (ADR 0002): update only affected entities, and re-sequence touched containers.
- The camera is editor state, and the UI reaches the viewport through injected closures (ADR 0003).
- The spec (`docs/spec/…`) §16–17 sketches cameras and lights; the parts named here are what gets built.

## Global Constraints

- Swift 6 strict concurrency: no `nonisolated(unsafe)` and no `@unchecked Sendable`. `MainActor.assumeIsolated` only where gama's `@MainActor` host guarantees it, as in the existing `StudioApp`.
- Strict memory safety is an error on library targets. A linear color becomes a platform color through `CGColor(srgbRed:green:blue:alpha:)` after sRGB encoding (reuse `Material.encodeSRGB`). Never use the pointer-taking `CGColor(colorSpace:components:)`.
- Every public symbol gets `///` documentation. Tests use Swift Testing only.
- Raise `MIN_TESTS` in `tools/check.sh` to the measured total in every task that adds tests.
- Run the gate as `./tools/check.sh >| log 2>&1; echo EXIT:$?`. If `swiftly run` fails to spawn, prefix `env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin:$HOME/.swiftly/bin`.
- Leave no `gama-studio` process running. Shell traps: use `>|`, `command rm -f`, `command cp -f`.

## Tasks

### Task 1: Authoring components

**Files:**
- `Sources/GamaAuthoring/Components.swift`, or a new `Lighting.swift` beside it, containing:
  - `public struct Light: Hashable, Codable, Sendable` holding `kind: LightKind`, `color: SIMD3<Float>` (linear, each channel in 0…1) and `intensity: Float` (finite, ≥ 0);
  - `public enum LightKind: Hashable, Codable, Sendable`: `.directional`, `.point(attenuationRadius: Float)` (> 0), and `.spot(innerAngleDegrees: Float, outerAngleDegrees: Float, attenuationRadius: Float)`, where 0 < inner ≤ outer < 180 and the radius is > 0;
  - `public struct CameraSettings: Hashable, Codable, Sendable` holding `fieldOfViewDegrees` (1…179), `near` (> 0) and `far` (> near), all finite, with defaults 60° / 0.01 / 1000.
- `validate() throws(AuthoringError)` on each type. Add `AuthoringError.invalidLight(String)` and `.invalidCamera(String)`.
- `Component` gains `.light(Light)` and `.camera(CameraSettings)`. `ComponentKind` gains `.light` and `.camera` after `.visibility`, with `displayName` values "Light" and "Camera". Every exhaustive switch gets its case.
- **Defaults:** `Light.defaultDirectional` has intensity 3000 (the editor light's value) and white color. `Light.defaultPoint` has a 10 m radius and an intensity that is visible at a few meters. Pick a lumen value close to RealityKit's point-light default of 26963.76, and document that it is RealityKit's unit.

**Tests** (`Tests/GamaAuthoringTests/`):
- Validation rejects each invalid field, and a refused `SetComponent` changes nothing.
- Add `CommandRoundTripTests.cases` entries for adding, changing and removing a light and a camera.
- JSON `Codable` round trip of a document containing both.
- Keep the import ban green.

### Task 2: Bridge projection and markers

**Files:** `Sources/GamaReality/RealityBridge.swift`, plus a new `LightProjection.swift`, plus `PrimitiveMeshes.swift` for the marker mesh and shape caches.

**Lights:** `.light` maps to exactly one of `DirectionalLightComponent`, `PointLightComponent` or `SpotLightComponent` on the entity. Removing the light, or changing its kind, removes the others. The RealityKit property names and initializers must be verified against the SDK swiftinterface. Color goes linear, then `encodeSRGB`, then `CGColor(srgbRed:…)`.

**Markers:**
- A camera or light entity gets one child marker entity, named `"GamaReality.marker"`, which the bridge does not map to an `EntityID`. Picking already walks up to the owner.
- The marker carries an `UnlitMaterial` model and a collision shape:
  - camera: a small box 0.2 × 0.15 × 0.3, dark grey;
  - light: a sphere of radius 0.1 in the light's color, clamped so it stays visible.
- An entity with both a camera and a light gets the camera marker.
- Markers are created and removed with the components. They don't count in `bridge.count` and aren't picked as their own ids.
- Markers inherit the entity's `isEnabled`.
- Markers must survive the sibling re-sequencing in `resequenceTouchedContainers`. That function walks mapped children only, so it must not drop or reorder unmapped marker children, or treat them as "foreign" in a way that breaks convergence.
- **A camera never gets a RealityKit camera component.**

**Tests** (`Tests/GamaRealityTests/`):
- Extend `NodeSnapshot` with the light kind and parameters, and with the marker's presence.
- Extend the seeded command generator to set and remove light and camera components.
- The convergence test must stay green over all seeds.
- Mapping tests: each light kind produces exactly one light component; a kind change swaps it; removal clears both the light and the marker; a camera never adds `PerspectiveCameraComponent`; the marker is pickable through the ancestor walk (`ViewportController.pickedEntityID` lives in Studio, so test with the same ancestor-walk logic, or leave it to Task 3).
- Update ADR 0002 with one decision bullet on lights and markers.

### Task 3: `StudioModel` actions, viewport fallback light, and Look through

**Files:** `Sources/GamaStudioEditor/StudioModel.swift`, `ViewportController.swift`, `StudioApp.swift` (the viewport-actions type only), and `Sources/gama-studio/main.swift`.

**`StudioModel`:**
- New actions:
  - `addLight(_ kind: LightKind)`: a root entity "Light N" with transform, light and visibility, selected; positioned above the scene;
  - `addCamera()`: "Camera N" with a transform looking at the origin from a sensible spot, and default `CameraSettings`; selected;
  - `cycleLightKind()`, `scaleLightIntensity(by:)`, `adjustFieldOfView(by:)`, all on the primary selection.
- Everything goes through the existing funnel.
- `public var onDocumentChange: (@MainActor () -> Void)?`, called after every applied change (edits, undo, redo).
- `sampleScene()` gains "Key Light" (directional, intensity 3000, aimed the way the editor light is now: from (3, 6, 4) toward the origin) and "Camera" (at (0, 3, 7), looking at the origin). The rotation is computed from look-at math in `GamaAuthoring`-free code: `StudioModel` may import Foundation, but the quaternion must be built by a small helper in Studio, not in the core.

**`ViewportController`:**
- `editorLight.isEnabled` is true iff the document has no enabled light. A light counts as enabled when its entity and every ancestor are visible, computed from the document.
- It is recomputed at init and in `model.onDocumentChange`. Keep the existing selection-change behavior.
- `lookThrough(_ id: EntityID)`: if the entity has a camera, set the orbit from its world transform (eye = position, target = eye + forward × current distance, where forward is the entity's −Z) and set `camera.camera.fieldOfViewInDegrees` from its `CameraSettings`. Otherwise do nothing.

**Viewport actions:**
- Replace `StudioApp(model:onFrameSelection:)` with `StudioApp(model:viewport: ViewportActions = .none)`.
- `public struct ViewportActions: Sendable` holds `frameSelection: @MainActor @Sendable () -> Void` and `lookThrough: @MainActor @Sendable (EntityID) -> Void`.
- Update `main.swift` and the existing tests.

**Tests:**
- The model actions: bridge equals rebuild after each one, refusals, and the sample scene now has six entities.
- Fallback: sample scene means editor light off; delete the Key Light and it's on; hide it and it's on; undo and it's off.
- Look through: the orbit target and eye match the camera's transform, and the FOV matches.
- Mutation: always enable the editor light, and a fallback test must fail.

### Task 4: UI

**File:** `Sources/GamaStudioEditor/StudioApp.swift`.
- Toolbar gains "Add Light" (`studio.addLight`, a point light) and "Add Camera" (`studio.addCamera`), and `StudioApp.toolbarActionIDs` is updated.
- The inspector shows, for a light: its kind (a button cycling the kinds), intensity with −/+ (scaling ×0.8 and ×1.25), and color as numbers. For a camera: FOV with −/+ in steps of 5°, near and far, and "Look through" (which calls `viewport.lookThrough`).
- Hierarchy rows get a light or camera hint in the text. The existing selection highlight stays.

**Tests** (`StudioAppTests`):
- The buttons change the model, and look-through calls the injected closure with the selected id.
- The inspector text shows the new fields.
- The existing tests stay green.

### Task 5: Docs and gate

- ADR `docs/adr/0004-cameras-and-lights-are-authored-components.md` (Context / Decision / Consequences):
  - the camera never drives the viewport;
  - markers;
  - the fallback editor light;
  - look-through is editor state;
  - the units (RealityKit lux for directional, lumens for point and spot);
  - macOS only.
- Update the "Not built" list in `AGENTS.md` (remove item 1, the camera and light components) and its layout; update `CLAUDE.md` and the README.
- The gate must pass.

## Verification

- The gate passes after each task, with the floor raised.
- Mutation checks as listed in Tasks 2 and 3.
- Visual check: the `--snapshot` PNG with the sample scene, now lit by the document's Key Light, with the camera and light markers visible.
- A whole-branch review, then fast-forward into `main`, remove the worktree and branch, and update the `~/CLAUDE.md` row.
