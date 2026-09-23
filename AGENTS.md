# AGENTS.md

This is the canonical guide for agents working in this repository. `CLAUDE.md` defers to it.

## What this is

Gama Studio is a document-centric 3D authoring app. It is not the gama UI framework (`donaldfilimon/gama`, checked out at `~/Desktop/Gama`) and not `~/dev/active/gama-qt`.
- The product vision is `docs/spec/2026-09-23-unified-usd-realitykit-spec.md`. It is **Vision**, not a capability claim: most of it is not built.
- What exists today is Phases 0 through 2:
  - `GamaAuthoring`: a tested authoring core with no renderer and no UI.
  - `GamaReality`: an Apple-only RealityKit projection of it.
  - `GamaStudioEditor` + the `gama-studio` executable: a macOS-only editor window built from Gama views (toolbar, scene hierarchy, inspector, status line) around a RealityKit viewport attached through a native region. Orbit camera controls (mouse: drag orbits, right/Option-drag pans, wheel zooms; trackpad: two-finger scroll orbits, Shift+scroll pans, pinch zooms), a toolbar "Frame" button (selection, or everything when nothing is selected), and click-to-select picking. See ADR 0003. Cameras and lights are authored document components (ADR 0004): the viewport lights from the document's own lights, falling back to a fixed editor light only when none is visible, and a camera or light entity shows as a pickable marker; "Look through" snaps the orbit camera to a selected camera's viewpoint and field of view, as editor state, never a document write.
- The repo is local-only with no remote. Commit on `main`.
- **`Package.swift` pins `donaldfilimon/gama` by revision, not by branch:** `2ef325c120674cfe218de44f492f435ff50a28e7`, the head of gama PR #108 (stacked on #107), because `NativeRegion` and `GamaHostView.attach(_:to:)` do not exist on gama's `main` yet. Neither PR is merged, and gama's hosted CI is still blocked by the account-wide billing lock (`~/CLAUDE.md`), so a red or missing gama check there is not evidence against this repo. **Bump the pinned revision to a `main` commit once gama #107/#108 merge, and re-run this repo's gate against it before treating the bump as routine.**

## Gate

```bash
./tools/check.sh >| check.log 2>&1; echo "EXIT:$?"
```

It is green only when the log ends with `check.sh: PASSED`. It runs, in order:
1. A toolchain assertion (6.5-dev).
2. The standard-library-only import ban on `Sources/GamaAuthoring`, which fails closed.
3. `swift build` with warnings as errors.
4. `swift test`, with a test-count floor (`MIN_TESTS`) applied to the sum over all test targets. Every target's run must pass.
5. `gama-studio --smoke`, which launches the real executable headless (one frame, no event loop): it asserts the host produced draw commands, the RealityKit `ARView` is an attached, visible, non-empty subview of the host, and the bridge's entity count matches the document's.

When you add tests, raise the floor. Never lower it to make the gate pass. The full gate takes over a minute, mostly the bridge convergence suite.

## Toolchain

- `.swift-version` pins `main-snapshot-2026-08-21`, the same pin as gama. Run `unset TOOLCHAINS`, then `swiftly run swift <build|test>`.
- The manifest stays `swift-tools-version: 6.4` to match gama.
- The platform floor is macOS 15 / iOS 18 / tvOS 26 / visionOS 1, set by RealityKit's cone and cylinder meshes (ADR 0002).
- Only macOS is built and tested. Other platforms are unmeasured.
- The repo sits outside iCloud, so `swift test` runs in place.
- Single suite: `swiftly run swift test --filter CommandRoundTripTests`. The filter matches the struct name, not the `@Suite` title. A filter that matches nothing exits 0, so check the count.

## Run

```bash
unset TOOLCHAINS
swiftly run swift run gama-studio                        # opens the editor window
swiftly run swift run gama-studio --smoke                # headless check; exits 0/1 (what the gate runs)
swiftly run swift run gama-studio --snapshot out.png      # renders one ARView frame to a PNG, exits 0 only if it isn't blank
```

`gama-studio` is macOS only (ADR 0003): it depends on `GamaStudioEditor`, which is gated on `canImport(AppKit)`/`canImport(RealityKit)`.

## Invariants (spec §64, as built here)

1. **The document is the source of truth.** No renderer, UI, or AI owns scene state.
2. **Every mutation is a `DocumentCommand` executed through `EditorSession`.** `SceneDocument` has no public mutators. UI, console, graphs, and AI must produce commands, never edit the document.
3. **A command returns its exact inverse.** Every new command needs a case in `CommandRoundTripTests.cases`. The test executes it, undoes it, redoes it, and undoes it again, comparing content each time.
4. **A refused edit changes nothing:** not the document, history, revision, selection, or `pendingChanges`. Commands validate their inputs and may throw midway, because the session applies them to a copy.
5. **`GamaAuthoring` imports nothing.** The gate enforces this. Platform code goes in a separate target that depends on it.
6. **Identifiers are deterministic and never reused.** Don't introduce `UUID` into the core.
7. **The change feed names what changed.** A projection reads current values from the document.
8. **The RealityKit bridge is read-only and incremental** (ADR 0002).
   - It never writes the document.
   - It skips changes naming entities a later change removed.
   - It re-sequences only the containers it touched, because RealityKit does not keep sibling order on removal.
   - Any change to the bridge must keep `BridgeConvergenceTests` green: incremental projection must equal a fresh rebuild after every drain.
9. **The editor UI never mutates state directly** (ADR 0003). Every panel, button, and the viewport's click handler go through `StudioModel`, which is the only caller of `EditorSession`'s mutating surface and the only place `bridge.apply` is called; dropping that call desyncs the bridge from the document, and `StudioModelTests` must fail if it does.
10. **A `@MainActor` crossing at the UI boundary is an explicit `MainActor.assumeIsolated`, never an assumption left silent** (ADR 0003): gama only runs a surface's content closure inside `FrameHost.pump` and an action inside `FrameHost.handle`/`perform`, both main-actor-only callers, so the assertion traps instead of racing if that stops holding.

Decisions and their reasons are in `docs/adr/` (0001: the value document and commands; 0002: the RealityKit bridge; 0003: Studio's Gama-hosted UI and the RealityKit viewport; 0004: cameras and lights as authored components).

## Layout

- `Sources/GamaAuthoring/`
  - `SceneDocument` (value document plus `validate()`)
  - `Commands` (create, delete, restore, duplicate, rename, set/remove component, reparent)
  - `EditorSession` (command bus, undo/redo, transactions, change feed, selection)
  - `Components` and `Math` (transform, mesh primitive, material, visibility)
  - `Lighting` (`Light`, `LightKind`, `CameraSettings`, ADR 0004)
  - `Selection`, `SceneChange`, `AuthoringError`
- `Sources/GamaReality/`: `RealityBridge` (entity maps, `apply`, `rebuild`, picking via `id(for:)`), `PrimitiveMeshes` (unit-size mesh cache, plus the camera/light marker mesh and shape cache), `MaterialProjection` (`PhysicallyBasedMaterial`), and `LightProjection` (light-component projection, marker color/kind, ADR 0004). Every file sits inside `#if canImport(RealityKit)`.
- `Sources/GamaStudioEditor/`: macOS-only editor UI (ADR 0003).
  - `StudioModel` (`@MainActor`): the funnel — owns `EditorSession` and `RealityBridge`, and is the only caller of either's mutating surface. Also holds the light/camera actions (`addLight`, `addCamera`, `cycleLightKind`, `scaleLightIntensity`, `adjustFieldOfView`) and `onDocumentChange`, ADR 0004.
  - `StudioApp` (`App`, gated on `canImport(AppKit)`): the Gama view tree — toolbar, `HierarchyPanel`, `NativeRegion(StudioApp.viewportRegion)`, `InspectorPanel`, status line — plus `StudioFrameState`, the `Sendable` per-frame snapshot built inside `MainActor.assumeIsolated`, and `ViewportActions` (`frameSelection`, `lookThrough`).
  - `ViewportController` (gated on `canImport(AppKit) && canImport(RealityKit)`): the `StudioViewportView: ARView` subclass, an orbit `PerspectiveCamera`, the fallback `editorLight` (on only when the document has no visible light, ADR 0004), click-to-select picking via `pickedEntityID(for:in:)`, and `lookThrough(_:)`.
  - `LookAt.swift`: `Rotation.lookAt(_:from:up:)`, the `simd`-based look-at helper `GamaAuthoring` cannot host itself (ADR 0004).
- `Sources/gama-studio/main.swift`: the executable. Owns the `NSApplication`/`NSWindow`/`GamaHostView`, installs `StudioApp`, attaches the `ViewportController`'s `ARView` to the viewport region. `--smoke` runs one frame headless and asserts the host, viewport, and bridge are in the state the gate checks; `--snapshot <path>` renders one `ARView` frame to a PNG and exits non-zero if it's blank.
- `Tests/GamaAuthoringTests/`: Swift Testing only. `SampleScene` in `Fixtures.swift` is the shared fixture.
- `Tests/GamaRealityTests/`: `@MainActor` suites.
  - `Support.swift` holds the tree snapshot, a copy of `SampleScene`, and a seeded command generator. Test targets can't share files.
  - `RealityBridgeTests.swift`: convergence, incrementality, and mapping tests.
  - `LightProjectionTests.swift`: light-component and marker projection, ADR 0004.
- `Tests/GamaStudioEditorTests/`: `@MainActor` suites — `StudioModelTests` (the funnel and bridge sync), `StudioAppTests` (frame state and view tree), `StudioAppDelegateTests`, `ViewportTests` (picking, host placement, and real `NSWindow.sendEvent` click/keyboard round trips), `OrbitCameraTests` (the camera math), `ViewportCameraTests` (input mapping, scroll routing by device, and a real window drag that orbits without selecting), `LightsAndCamerasTests` (the sample scene's Key Light/Camera, the model's light/camera actions, the fallback light, and "Look through", ADR 0004), `Support.swift` (shared fixtures; test targets can't share files across targets).

## Not built (next phases, in order)

1. **Selection highlighting** in the viewport.
2. **A USD stage abstraction plus save/load**, implemented against the real SDK APIs, never invented signatures.
3. **A command console** that parses into the same commands.
4. **A typed graph framework.**
5. **iOS and visionOS hosting.** `StudioModel` compiles wherever RealityKit does; `StudioApp`, `ViewportController`, and `gama-studio` are AppKit-only today.

None of these may be described as existing until it has a target and passing tests.
