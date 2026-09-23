# AGENTS.md

This is the canonical guide for agents working in this repository. `CLAUDE.md` defers to it.

## What this is

Gama Studio is a document-centric 3D authoring app. It is not the gama UI framework (`donaldfilimon/gama`, checked out at `~/Desktop/Gama`) and not `~/dev/active/gama-qt`.
- The product vision is `docs/spec/2026-09-23-unified-usd-realitykit-spec.md`. It is **Vision**, not a capability claim: most of it is not built.
- What exists today is Phases 0 through 2:
  - `GamaAuthoring`: a tested authoring core with no renderer and no UI.
  - `GamaReality`: an Apple-only RealityKit projection of it.
  - Typed node graphs (ADR 0007): `GraphDocument`s live in `SceneDocument` and change only through graph commands. `GamaGraph` (standard library only) evaluates them; output nodes emit ordinary `SetComponent`s (Material Output, Transform Output), and editors bundle each graph edit with `EvaluateGraph` so the scene effect undoes with it. The editor's "Graph" toolbar toggle swaps the inspector for the graph panel.
  - `GamaConsole`: a standard-library-only command-console parser; each line becomes the same `DocumentCommand`s the panels produce, or the same `StudioModel` call the toolbar makes (ADR 0006). The editor shows it as a "Console" panel above the status line.
  - `GamaUSD`: a standard-library-only USDA writer and reader with an exact round trip (ADR 0005). The File menu (⌘O/⌘S/⇧⌘S) and `--open`/`--export` use it.
  - `GamaStudioEditor` + the `gama-studio` executable: a macOS-only editor window built from Gama views (toolbar, scene hierarchy, inspector, status line) around a RealityKit viewport attached through a native region. Orbit camera controls (mouse: drag orbits, right/Option-drag pans, wheel zooms; trackpad: two-finger scroll orbits, Shift+scroll pans, pinch zooms), a toolbar "Frame" button (selection, or everything when nothing is selected), click-to-select picking, and an orange wireframe box around each selected entity (editor state beside `bridge.root`, never in the document or the bridge, unpickable; follows every selection source through `StudioModel.onSelectionChange`). See ADR 0003. Cameras and lights are authored document components (ADR 0004): the viewport lights from the document's own lights, falling back to a fixed editor light only when none is visible, and a camera or light entity shows as a pickable marker; "Look through" snaps the orbit camera to a selected camera's viewpoint and field of view, as editor state, never a document write.
- The repo is local-only with no remote. Commit on `main`.
- **`Package.swift` pins `donaldfilimon/gama` by revision, not by branch:** `2ef325c120674cfe218de44f492f435ff50a28e7`, the head of gama PR #108 (stacked on #107), because `NativeRegion` and `GamaHostView.attach(_:to:)` do not exist on gama's `main` yet. Neither PR is merged, and gama's hosted CI is still blocked by the account-wide billing lock (`~/CLAUDE.md`), so a red or missing gama check there is not evidence against this repo. **Bump the pinned revision to a `main` commit once gama #107/#108 merge, and re-run this repo's gate against it before treating the bump as routine.**

## Gate

```bash
./tools/check.sh >| check.log 2>&1; echo "EXIT:$?"
```

It is green only when the log ends with `check.sh: PASSED`. It runs, in order:
1. A toolchain assertion (6.5-dev).
2. The standard-library-only import ban on `Sources/GamaAuthoring`, `Sources/GamaUSD`, `Sources/GamaConsole`, and `Sources/GamaGraph`, which fails closed.
3. `swift build` with warnings as errors.
4. `swift test`, with a test-count floor (`MIN_TESTS`) applied to the sum over all test targets. Every target's run must pass.
5. `gama-studio --smoke`, which launches the real executable headless (one frame, no event loop): it asserts the host produced draw commands, the RealityKit `ARView` is an attached, visible, non-empty subview of the host, and the bridge's entity count matches the document's.
6. `usd` (ADR 0005): `gama-studio --export` writes the sample scene, `usdchecker` must report `Success!`, every golden in `Tests/GamaUSDTests/Fixtures` must pass `usdchecker` too, `usdcat` reformats the export, and `--open` of that plus `--export` must reproduce the first export byte for byte. It fails closed when Apple's USD tools are missing.
7. `ios and visionos` (ADR 0008): the library and the app build for both simulators with Xcode's toolchain, and the app launched with `--smoke` on `iPhone 17` and `Apple Vision Pro` (overridable with `GAMA_STUDIO_IOS_SIMULATOR` / `GAMA_STUDIO_VISIONOS_SIMULATOR`) must print its OK line (the smoke includes a sandboxed `.usda` write and read-back, ADR 0009). The stage also requires the built app's Info.plist to declare the `.usda` document type and open-in-place, and a second launch with `--smoke --open` on `Tests/GamaUSDTests/Fixtures/everything.usda` copied into the app's container (ADR 0010); that launch also opens it as a coordinated `UIDocument`, autosaves an edit, reloads after another writer's coordinated write, and asks when that write meets unsaved changes (ADR 0011). It also requires those events' console notes, in order: opened, autosaved, reloaded, kept your version (ADR 0017). The plain `--smoke` launch also drives the touch viewport (pick, orbit, pinch, Frame, Look through) and requires its notes in order (ADR 0018). Two more launches per simulator share a random `--recovery-key`: `--smoke-recovery write` must autosave unsaved Untitled changes to the recovery file, and `--smoke-recovery restore --open <fixture>` must find them restored as unsaved Untitled changes and the recovery file gone once a file opens (ADR 0012). Before the first of those, the gate plants an 8-day-old and a fresh orphan recovery file; only the old one may be swept (ADR 0013). Two more launches: `--adopt-orphans --smoke-recovery adopt` must adopt a planted orphan as unsaved Untitled changes, and `--smoke-recovery discard` must sweep made-up discarded keys with the grace period (ADR 0014).

When you add tests, raise the floor. Never lower it to make the gate pass. The full gate takes over a minute, mostly the bridge convergence suite.

## Toolchain

- `.swift-version` pins `main-snapshot-2026-08-21`, the same pin as gama. Run `unset TOOLCHAINS`, then `swiftly run swift <build|test>`.
- The manifest stays `swift-tools-version: 6.4` to match gama.
- The platform floor is macOS 15 / iOS 18 / tvOS 26 / visionOS 2: RealityKit's cone and cylinder meshes (ADR 0002), and on visionOS the runtime for typed-throws closures and `DirectionalLight` (ADR 0008).
- macOS is built and unit-tested with the swiftly snapshot. iOS and visionOS are built with Xcode's toolchain and launch-smoked in simulators by the gate (ADR 0008); tvOS is unmeasured.
- The repo sits outside iCloud, so `swift test` runs in place.
- Single suite: `swiftly run swift test --filter CommandRoundTripTests`. The filter matches the struct name, not the `@Suite` title. A filter that matches nothing exits 0, so check the count.

## Run

```bash
unset TOOLCHAINS
swiftly run swift run gama-studio                        # opens the editor window
swiftly run swift run gama-studio --smoke                # headless check; exits 0/1 (what the gate runs)
swiftly run swift run gama-studio --snapshot out.png      # renders one ARView frame to a PNG, exits 0 only if it isn't blank
swiftly run swift run gama-studio --open scene.usda       # starts from a file instead of the sample scene
swiftly run swift run gama-studio --export out.usda       # writes the document (sample, or --open's) and exits; builds no UI
```

`gama-studio` is the macOS host (ADR 0003). iOS and visionOS run `Apps/GamaStudioApp/GamaStudioApp.xcodeproj` (ADR 0008), a thin SwiftUI app over the `GamaStudioEditor` product, built with Xcode's toolchain:

```bash
env -u TOOLCHAINS xcodebuild -project Apps/GamaStudioApp/GamaStudioApp.xcodeproj -scheme GamaStudio \
  -destination 'generic/platform=iOS Simulator' build        # or 'generic/platform=visionOS Simulator'
xcrun simctl launch --console-pty <udid> com.donaldfilimon.GamaStudio --smoke   # prints the smoke verdict
```

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

Decisions and their reasons are in `docs/adr/` (0001: the value document and commands; 0002: the RealityKit bridge; 0003: Studio's Gama-hosted UI and the RealityKit viewport; 0004: cameras and lights as authored components; 0005: USDA persistence; 0006: the command console; 0007: the typed graph framework; 0008: iOS and visionOS hosting; 0009: file open and save on iOS and visionOS; 0010: opening .usda files from other apps; 0011: autosave and UIDocument coordination; 0012: Untitled autosave to a recovery file; 0013: orphaned recovery file cleanup; 0014: sweeping and adopting on discarded sessions; 0015: the recovered-changes notice; 0016: that notice as a console note; 0017: editor events as console notes; 0018: viewport events as console notes; 0019: Save As resolving a picked folder; 0020: iPad portrait toolbar fits).

## Layout

- `Sources/GamaAuthoring/`
  - `SceneDocument` (value document plus `validate()`)
  - `Commands` (create, delete, restore, duplicate, rename, set/remove component, reparent)
  - `EditorSession` (command bus, undo/redo, transactions, change feed, selection)
  - `Components` and `Math` (transform, mesh primitive, material, visibility)
  - `Lighting` (`Light`, `LightKind`, `CameraSettings`, ADR 0004)
  - `Graph` (`GraphDocument`, `GraphNode`, `GraphPort`, `PortType`, `GraphValue`, `GraphConnection`, `GraphDomain`) and `GraphCommands` (the graph edits plus `CompositeCommand`), ADR 0007
  - `Selection`, `SceneChange`, `AuthoringError`
- `Sources/GamaGraph/`: `NodeDefinition`/`NodeRegistry` (with `.standard`), `StandardNodes`, `GraphEvaluator`, `EvaluateGraph`, `GraphError`. Standard library only (ADR 0007).
- `Sources/GamaConsole/`: `ConsoleParser` (tokenizer, target resolution, one function per verb, `usage` table that `help` prints), `GraphVerbs` (the `graph` verb family), `ConsoleAction`, `ConsoleWord`, `ConsoleError`. Standard library only (ADR 0006).
- `Sources/GamaUSD/`: `usdaString(from:)` (`USDAWriter`), `sceneDocument(fromUSDA:)` (`USDAReader`, over `USDALexer`/`USDAParser`), `USDSchema` (the names both sides share), and `USDError`. Standard library only (ADR 0005).
- `Sources/GamaReality/`: `RealityBridge` (entity maps, `apply`, `rebuild`, picking via `id(for:)`), `PrimitiveMeshes` (unit-size mesh cache, plus the camera/light marker mesh and shape cache), `MaterialProjection` (`PhysicallyBasedMaterial`), and `LightProjection` (light-component projection, marker color/kind, ADR 0004). Every file sits inside `#if canImport(RealityKit)`.
- `Sources/GamaStudioEditor/`: macOS-only editor UI (ADR 0003).
  - `StudioModel` (`@MainActor`): the funnel — owns `EditorSession` and `RealityBridge`, and is the only caller of either's mutating surface. Also holds the light/camera actions (`addLight`, `addCamera`, `cycleLightKind`, `scaleLightIntensity`, `adjustFieldOfView`) and `onDocumentChange`, ADR 0004. `runConsole`/`submitConsole` run console lines through the same funnel and keep `consoleInput` and a bounded `consoleLog` (ADR 0006).
  - `StudioApp` (`App`, gated on `canImport(AppKit)`): the Gama view tree — toolbar, `HierarchyPanel`, `NativeRegion(StudioApp.viewportRegion)`, `InspectorPanel`, status line — plus `StudioFrameState`, the `Sendable` per-frame snapshot built inside `MainActor.assumeIsolated`, and `ViewportActions` (`frameSelection`, `lookThrough`).
  - `ViewportController` (gated on `canImport(AppKit) && canImport(RealityKit)`): the `StudioViewportView: ARView` subclass, an orbit `PerspectiveCamera`, the fallback `editorLight` (on only when the document has no visible light, ADR 0004), click-to-select picking via `pickedEntityID(for:in:)`, and `lookThrough(_:)`.
  - `StudioDocumentIO`: `.usda` file read and write, the only Foundation-to-disk path, plus `describe(_:)` for alerts. `StudioAppDelegate` owns the File menu, `currentURL`, the window title and edited dot, and the Save / Don't Save / Cancel prompts. `StudioModel.replaceDocument` and `hasUnsavedChanges` back them (ADR 0005). `StudioDocumentSession` is the file core the File menu and the touch pickers share: current file, security-scoped read/write, export copies, saved state (ADR 0009).
  - `SelectionHighlight` (gated like `ViewportController`): the wireframe selection box, 12 thin unlit edges per selected entity around its padded world-space `visualBounds` (hidden entities included). `StudioModel.onSelectionChange` fires on any selection change, whatever caused it, after `onDocumentChange`.
  - `TouchViewport` (UIKit + RealityKit + SwiftUI): the iOS/visionOS `RealityView` viewport, `StudioTouchHost` (`StudioHostViewController`, `GamaStudioView`, the launch smoke check), and `ViewportSupport` (picking and fallback-light rules shared with `ViewportController`), ADR 0008. `StudioRootView` switches to a compact layout below 86 columns. `TouchDocuments` (`TouchDocumentController`) presents the document picker for Open and Save As, and the unsaved-changes prompt; `StudioApp` shows Open/Save/Save As buttons only when a host passes `DocumentActions` (ADR 0009). Files handed over by the system arrive through the app's `onOpenURL` as an `IncomingDocument`, then `StudioHostViewController.openExternalDocument` and `TouchDocumentController.openExternally` (ADR 0010); the app's `Info.plist` declares the type. `StudioUIDocument` (UIKit) holds the current file for coordinated reads and writes and in-place autosave; it never touches the model, passing `SceneDocument` values through a `Mutex` and naming itself by `ObjectIdentifier` in events (ADR 0011). An Untitled document with unsaved changes autosaves to a private recovery file through a second `StudioUIDocument`; `UntitledRecovery` (platform-neutral) names, restores, and removes it, keyed by the window's scene session (ADR 0012). On each window's first appearance, `UntitledRecovery.sweepOrphans` deletes recovery files of windows the system no longer keeps (`UIApplication.shared.openSessions`) once they are 7 days unmodified (ADR 0013). `StudioApplicationDelegate` (installed with `@UIApplicationDelegateAdaptor`) repeats that sweep when sessions are discarded, and a window with no recovery file adopts the newest young orphan; `RecoveryWindows` registers this process's window keys (ADR 0014). `StudioModel.notice` is a one-time status-line message, set by `UntitledRecovery.restore(into:adopted:)` and cleared by the next document change (ADR 0015); `post(notice:)` also keeps it in the console log as a note (`ConsoleEntry.isNote`, rendered `· …`, ADR 0016). `log(note:isError:coalescing:)` records file events, coordination, autosaves (coalesced), and button refusals (not typed ones, via a console-depth guard); `onConsoleChange` makes hosts repaint for notes that arrive outside gama actions (ADR 0017). `ViewportSupport.notePick`/`noteFrame`/`noteLookThrough`/`noteCameraMove` give both viewports the same coalesced notes for viewport picks, Frame, Look through, and camera moves (ADR 0018). Save As passes the picker's result through `ExportedFile.resolve` (platform-neutral) before adopting it: "Keep Both" hands back the destination folder, which resolves to the fresh copy inside it (same bytes, written since Save As began) or to a reported failure that leaves the current file, saved state, and Untitled recovery untouched (ADR 0019).
  - `LookAt.swift`: `Rotation.lookAt(_:from:up:)`, the `simd`-based look-at helper `GamaAuthoring` cannot host itself (ADR 0004).
- `Sources/gama-studio/main.swift`: the executable. Owns the `NSApplication`/`NSWindow`/`GamaHostView`, installs `StudioApp`, attaches the `ViewportController`'s `ARView` to the viewport region. `--smoke` runs one frame headless and asserts the host, viewport, and bridge are in the state the gate checks; `--snapshot <path>` renders one `ARView` frame to a PNG and exits non-zero if it's blank.
- `Tests/GamaGraphTests/`: `GraphEvaluatorTests` (both specializations end to end, saturation, inert targets, refusals, every standard node).
- `Tests/GamaConsoleTests/`: `ConsoleParserTests` (console versus direct command equality, targets, errors, session-side refusal) and `GraphVerbTests` (the `graph` verbs).
- `Tests/GamaUSDTests/`: round trips, refusals with line numbers, and `FixtureTests` against `Fixtures/everything.usda` (golden; `GAMA_UPDATE_GOLDEN=1` regenerates it) and `Fixtures/everything.usdcat.usda` (`usdcat` of the golden, verbatim). Regenerate the second with `usdcat` after any format change.
- `Tests/GamaAuthoringTests/`: Swift Testing only. `SampleScene` in `Fixtures.swift` is the shared fixture.
- `Tests/GamaRealityTests/`: `@MainActor` suites.
  - `Support.swift` holds the tree snapshot, its own `SampleScene` (separate from `Tests/GamaAuthoringTests/Fixtures.swift`'s — test targets can't share files, and the two have diverged: the authoring fixture's `Camera` carries transform, light, and camera components, this one's does not), and a seeded command generator.
  - `RealityBridgeTests.swift`: convergence, incrementality, and mapping tests.
  - `LightProjectionTests.swift`: light-component and marker projection, ADR 0004.
- `Tests/GamaStudioEditorTests/`: `@MainActor` suites — `StudioModelTests` (the funnel and bridge sync), `StudioAppTests` (frame state and view tree), `StudioAppDelegateTests`, `ViewportTests` (picking, host placement, and real `NSWindow.sendEvent` click/keyboard round trips), `OrbitCameraTests` (the camera math), `ViewportCameraTests` (input mapping, scroll routing by device, and a real window drag that orbits without selecting), `LightsAndCamerasTests` (the sample scene's Key Light/Camera, the model's light/camera actions, the fallback light, and "Look through", ADR 0004), `SelectionHighlightTests` (edge geometry, following every selection source and edit, editor-state isolation), `DocumentReplacementTests` and `StudioDocumentTests` (ADR 0005), `StudioDocumentSessionTests` (the shared file core and the toolbar file buttons, ADR 0009), `UntitledRecoveryTests` (ADR 0012-0016), `ConsoleNotesTests` (ADR 0017), `ViewportNotesTests` (ADR 0018), `ExportedFileTests` (Save As folder resolution, ADR 0019), `IPadToolbarWrapTests` (regular-layout toolbar wrap at the iPad-portrait column count, with and without file buttons, ADR 0020), `ConsoleTests` (the console through the model funnel and the panel's Enter-to-submit field, ADR 0006), `GraphPanelTests` (the graph editor driven by its buttons, refusals, editor state, save and reopen, ADR 0007), `Support.swift` (shared fixtures; test targets can't share files across targets).

## Not built (next phases, in order)

1. **Graph follow-ups** (ADR 0007): texture, mesh, and execution nodes; rotation in the transform output; a spatial node canvas; typed non-float constants in the panel.
2. **Reading USD Gama did not write, and `.usdz`** (ADR 0005, Proposed).
3. **Console follow-ups** (ADR 0006): `rotate`, `find`, history recall, a focus shortcut.
4. **iOS and visionOS follow-ups** (ADR 0008, ADR 0009): a software-keyboard route to the console, a visionOS volume, device signing, iCloud conflicts (ADR 0011), showing or reopening orphaned recovery files during their grace period (ADR 0013), adopting a Save As copy only after its attach succeeds (ADR 0019), macOS autosave.

None of these may be described as existing until it has a target and passing tests.
