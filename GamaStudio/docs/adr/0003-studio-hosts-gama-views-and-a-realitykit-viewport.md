# ADR 0003: Studio hosts Gama views and a RealityKit viewport via a native region

Status: Accepted (2026-09-23)

## Context

Phase 1 (ADR 0002) gave Gama Studio a document, commands, and a read-only
RealityKit projection, but no UI: nothing built the projection into a window
or let a person click an entity. AGENTS.md's Phase-2 item asked for "an
editor UI of Gama views with a native RealityKit viewport in the Apple
shell," and flagged that embedding a native view is a gama design question,
to be raised there first.

That question was raised and answered upstream: gama's own
`docs/adr/0016-native-regions-narrow-own-the-rendering.md`, in gama at
`2ef325c120674cfe218de44f492f435ff50a28e7` (the pinned revision below; the
ADR ships on gama PR #107/#108, not on gama's `main`, and is not tracked in
this repo), added `NativeRegion`, a Gama view that reserves a rectangle in
the retained layout
for a platform-native view an app attaches out of band, and
`GamaHostView.attach(_:to:)`/`install` on the Apple shell
(`GamaAppleUI`/`GamaAppleShell`) to do the attaching.
Gama Studio depends on that work directly: `Package.swift` pins
`donaldfilimon/gama` to revision `2ef325c120674cfe218de44f492f435ff50a28e7`,
the head of gama PR #108 (stacked on PR #107, which introduces
`NativeRegion` itself). Neither PR is merged; gama's hosted CI is still
blocked by the account-wide GitHub Actions billing lock recorded in
`~/CLAUDE.md`, so their checks read as unmeasured, not green, and that is a
property of gama's repository, not evidence against this branch's own gate.

A second question ADR 0002 left open was where a native view's clicks and
key events go once Gama also wants keyboard focus in the same window:
`FrameHost` and the AppKit shell own focus and action dispatch for Gama's
own views, but a `NativeRegion`'s content is opaque to Gama.

## Decision

1. **`GamaStudioEditor` owns a `StudioApp: App`, not `GamaShell`.**
   `GamaShell`'s own host view type is package-internal to gama, so an
   external app cannot construct one directly; the public surface is
   `GamaHostView` (`GamaAppleUI`) plus `App`/`Scene`/`View` (`GamaCore`).
   `StudioApp` declares one `Window("Gama Studio", id: "main", role:
   .primary)` whose content is a toolbar, a `HierarchyPanel`, a
   `NativeRegion(StudioApp.viewportRegion)`, an `InspectorPanel`, and a
   status line — all ordinary Gama views rebuilt from `StudioModel` every
   frame, per gama's existing per-surface `@Reactive`/`FrameHost` contract.
   The `gama-studio` executable (`Sources/gama-studio/main.swift`) is the
   only place that owns an `NSWindow`, an `NSApplication`, and the
   `GamaHostView` that fills it: it constructs `StudioApp`, installs it with
   `hostView.install(app:)`, then attaches a RealityKit view to
   `StudioApp.viewportRegion` with `hostView.attach(_:to:)`. Studio, not
   gama, owns process lifecycle and window chrome; gama owns everything
   drawn inside the window except the one native rectangle.
2. **The viewport is an app-owned `ARView`, not a Gama view.**
   `ViewportController` (`Sources/GamaStudioEditor/ViewportController.swift`)
   wraps a `StudioViewportView: ARView` subclass, parents `StudioModel`'s
   `bridge.root` under an anchor, and adds a fixed `PerspectiveCamera` and
   `DirectionalLight` so the sample scene is framed and lit without any
   camera or light components existing in the document yet (those remain
   Phase-2/3 work, tracked below). It never talks to gama's retained tree;
   `NativeRegion` only reserves the rectangle `GamaHostView` sizes and
   places it into every frame. `StudioViewportView` overrides
   `acceptsFirstMouse(for:)` so a click in a background window's viewport
   picks immediately, matching how a canvas behaves in other editors, and
   so a click delivered to an inactive process (the test runner) still
   reaches the gesture recognizer.
3. **Every read crosses into `@MainActor` state through
   `MainActor.assumeIsolated`, and so does every action.** `App` is a
   nonisolated protocol and `Button` stores a plain `() -> Void`, while
   `StudioModel` is `@MainActor`. This is sound because gama itself runs a
   surface's content closure only inside `FrameHost.pump` and a button's
   action only inside `FrameHost.handle`/`perform`, and the only callers of
   those here are `GamaHostView` (`@MainActor`) and the `@MainActor` test
   suites — so the assertion traps rather than races if that separation
   ever stops holding, instead of silently miscompiling. `StudioFrameState`
   is the `Sendable` snapshot built inside that assertion (entity rows,
   the inspected selection, revision, undo label, last error) that the view
   tree is built from once it leaves `assumeIsolated`; a Gama view tree
   itself cannot leave `assumeIsolated`, because it holds non-`Sendable`
   action closures.
4. **`StudioModel` is the only path to a mutation**, continuing invariant 2
   from `AGENTS.md`: every button, the viewport's click handler, and any
   future console all call one of `StudioModel`'s methods
   (`addPrimitive`, `deleteSelection`, `nudgeSelection`, `select`, `undo`,
   `redo`, …), never `EditorSession` or `RealityBridge` directly.
   `StudioModel.run`/`settle` fold `session.execute` and
   `bridge.apply(session.drainChanges(), from:)` into one call, so `bridge`
   cannot observe a document state the session never committed to, and a
   refused command leaves both untouched (`StudioModelTests` pins this;
   dropping the `bridge.apply` call is the mutation this task's gate must
   catch).
5. **Picking walks up the entity's ancestors, not just the hit itself.**
   `ViewportController.pickedEntityID(for:in:)` resolves the nearest
   ancestor `RealityBridge` actually projected, so a click on a sub-part the
   bridge did not create directly (RealityKit's own mesh submeshes, or
   anything future code parents under a projected entity) still resolves to
   the entity that owns it. It relies entirely on ADR 0002's bullet 9 —
   collision shapes projected alongside meshes — for there to be anything to
   hit; without a collision shape, picking silently does nothing, which is
   why removing the collision projection would be a regression this ADR
   depends on, not just ADR 0002. At the time this decision was written,
   `pick(at:)` called `arView.entity(at:)` directly; ADR 0004 decision 8
   replaces that with a `hitTest` + nearest-hit rule that also skips a hit
   at or below `insideHitDistance` (1e-4 m), for cameras and their markers.
6. **Keyboard focus after a click follows AppKit's own first-responder
   handoff, and Gama still receives it.** A click makes `StudioViewportView`
   first responder, as AppKit does for any view that accepts it. Nothing is
   done to prevent or reroute that. It works anyway because `ARView.keyDown`
   forwards the keys `ViewportTests` actually sends it — Enter, Tab, and
   Right — to `nextResponder`, which is `GamaHostView`, so those keys
   continue driving Gama's own focus and action dispatch after a viewport
   click; no other key has been measured, and this ADR does not claim
   `ARView` forwards "any key it does not consume" in general. A click does
   *not* move Gama's own focus onto the region: Gama focus stays on whatever
   control was last focused before the click, which is why pressing Enter
   right after a viewport click activates that control (in
   `windowClickSelectsAndKeysStillReachGama`, the first Enter after the click
   adds a box, because focus was still sitting on the "Add Box" toolbar
   button). Whether a click should instead move pointer focus onto the
   region itself is an open question for gama's own
   `docs/adr/0016-native-regions-narrow-own-the-rendering.md`, not something
   this ADR decides. This is a measured property of `ARView`, not a
   Studio-authored bridge, and `ViewportTests` pins it with a real
   `NSWindow.sendEvent` round trip (`windowClickSelectsAndKeysStillReachGama`)
   plus the reverse direction — Gama focus reaching the region by keyboard
   still hands the `ARView` first responder on the next click
   (`gamaFocusOnTheRegionStillHandsTheViewportFirstResponder`) — so a
   regression in either direction fails a test, not just a manual check.

## Consequences

- **macOS only.** `ViewportController` and `StudioApp` are gated on
  `canImport(AppKit) && canImport(RealityKit)` /
  `canImport(AppKit)` respectively; `StudioModel` alone is gated on
  `canImport(RealityKit)` so it still compiles on any RealityKit platform.
  iOS, tvOS, and visionOS hosting of `StudioApp` is unbuilt and unmeasured,
  same caveat ADR 0002 already carries for `GamaReality` itself.
- **The camera is user-driven editor state, not authored state.**
  `ViewportController` drives one `PerspectiveCamera` from an `OrbitCamera`
  value (target, yaw, pitch clamped to ±85°, distance clamped to 0.5–100 m).
  Input is chosen by device (added 2026-09-23): a mouse orbits with
  left-drag, pans with right-drag or Option+left-drag, and zooms with the
  notched wheel; a trackpad (scroll events with precise deltas) orbits with
  two-finger scroll, pans with Shift+scroll, and zooms with pinch. A drag
  makes the click recognizer fail, so dragging never changes the selection.
  No key is used, so decision 6's keyboard behavior is unchanged. The
  toolbar's "Frame" button aims the camera at the primary selection's
  visual bounds (or the whole scene with nothing selected), keeping the
  viewing direction; it reaches the viewport through a closure the host
  injects into `StudioApp(model:viewport: ViewportActions)`, so `StudioModel` stays
  free of camera state and framing is not an edit. The camera
  is not a document command: it is not undoable, not saved, and not shared
  with any other view. Camera components in the document remain unbuilt
  (AGENTS.md "Not built") — **now built; see ADR 0004**, which keeps this
  camera-is-editor-state decision unchanged even after the document gained
  its own `CameraSettings` component.
- **Click picking is exactly as good as ADR 0002's collision projection.**
  A primitive with no `ModelComponent`, or a future primitive kind added to
  `GamaReality` without a matching `CollisionComponent`, becomes unpickable
  without anything failing loudly; there is no independent hit-test path.
- **The pinned gama revision is a real, unmerged dependency, not a
  convenience pin.** `Package.swift` names `2ef325c120674cfe218de44f492f435ff50a28e7`
  because `NativeRegion` and `GamaHostView.attach(_:to:)` do not exist on
  gama's `main` yet. **Bump the dependency to a `main` revision once gama
  PRs #107 and #108 merge**, and re-verify this repo's gate against it
  before treating that bump as routine — a merged `NativeRegion` could
  still change shape during gama's own review. Until then, every green run
  of `./tools/check.sh` here is evidence about this repo against that one
  pinned commit, not about gama's `main`.
- **This ADR does not cover:** camera or light authoring in the document
  (still Phase 2 when this ADR was written — **now ADR 0004**), a command
  console, a typed graph framework, USD save/load, or any non-macOS
  backend. Those remain future ADRs, not silent extensions of this one.
