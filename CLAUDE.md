# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Read `AGENTS.md` first. It is the canonical guide: the gate, the toolchain, the invariants, and what isn't built yet. This file only adds the architecture in one picture.

```text
StudioApp (toolbar, HierarchyPanel, InspectorPanel)  ──┐
NativeRegion(viewportRegion) ──► GamaHostView.attach ──┤  gama's Apple shell (GamaAppleUI, unmerged gama #107/#108)
                                                        │
ViewportController ──► StudioViewportView: ARView      │  click ──► pickedEntityID(for:in:) ──┐
   orbit PerspectiveCamera + fallback DirectionalLight  │  lookThrough(_:) sets orbit from an   │
   (fallback on only when the document has no light)    │  authored camera's transform + FOV    │
                                                        ▼                                       ▼
UI / console / graph / AI  ──►  StudioModel  ──►  DocumentCommand  ──►  EditorSession
        (GamaStudioEditor,                             │  apply to a copy of SceneDocument
         the only caller of                            │  validate() the copy
         EditorSession/RealityBridge's                 │  commit, or discard on any error
         mutating surface — ADR 0003)                  ├─► undo/redo stacks (exact inverses)
                                                        ├─► selection (pruned, not history)
                                                        └─► pendingChanges ──► drainChanges() ──► RealityBridge.apply (GamaReality) ──► bridge.root parented under the viewport's anchor
```

Commands:

```bash
unset TOOLCHAINS
./tools/check.sh >| check.log 2>&1; echo "EXIT:$?"         # the gate: build, tests, --smoke, usd round trip
swiftly run swift test --filter TransactionTests           # one suite
swiftly run swift test --filter BridgeConvergenceTests     # bridge property test (~30–40 s)
swiftly run swift run gama-studio                           # open the editor window
swiftly run swift run gama-studio --smoke                   # what the gate runs, headless
swiftly run swift run gama-studio --snapshot out.png        # one ARView frame to PNG
swiftly run swift run gama-studio --export out.usda         # headless USDA export (ADR 0005)
```

- Adding a command means three things:
  1. Implement `apply(to:changes:)` so it returns the exact inverse.
  2. Add a case to `CommandRoundTripTests.cases`.
  3. Raise `MIN_TESTS` in `tools/check.sh`.
- RealityKit's `ChildCollection` reorders siblings on removal, so never rely on child order surviving a `removeFromParent`. The bridge re-sequences touched containers at the end of each pass (ADR 0002).
- `Package.swift` pins `donaldfilimon/gama` to a specific commit, `2ef325c120674cfe218de44f492f435ff50a28e7` (gama PR #108's head, stacked on #107, both unmerged, hosted CI blocked by the billing lock in `~/CLAUDE.md`). Bump it to a `main` revision once those merge, and re-run the gate against the bump before trusting it (ADR 0003).
- Every editor mutation goes through `StudioModel`, never `EditorSession` or `RealityBridge` directly, and every `@MainActor` crossing at the UI boundary is an explicit `MainActor.assumeIsolated` (ADR 0003).
- Lights and cameras are ordinary document components (`Light`, `CameraSettings` in `GamaAuthoring`), projected into RealityKit light components and pickable markers; a camera never becomes a RealityKit camera, and "Look through" is editor-only state, not a document write (ADR 0004).
- USD persistence is Gama's own stdlib-only USDA codec (`GamaUSD`), not `Entity.write` or ModelIO; `gama:` attributes are authoritative on read, and a format change means regenerating both fixtures in `Tests/GamaUSDTests/Fixtures` (ADR 0005).
- Agent shells may set `noclobber`: truncate with `>|`, and verify file edits by grepping for a marker rather than trusting an exit code.
