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
- iOS/visionOS (ADR 0008): the app builds with Xcode's Swift 6.4 (`env -u TOOLCHAINS xcodebuild`), not the swiftly snapshot, so keep the package 6.4-compatible. Never invalidate the gama host synchronously from a model listener; defer it (a button's edit runs inside the host's dispatch and re-entering traps). Synthetic simulator-tool taps do not reach visionOS apps; verify visionOS input with Device Hub clicks. File I/O on those platforms goes through `StudioDocumentSession` (shared with the macOS File menu) and the document picker (ADR 0009); keep new file logic in the session, not in a host. Files handed over by the system (ADR 0010) enter through `onOpenURL` in the app and `openExternalDocument`; test that route in a simulator with `xcrun simctl openurl <udid> file://...`, and on launch with `--smoke --open <path>`. `simctl openurl` delivers a copy in `Documents/Inbox`, not the original (ADR 0011). Coordination (ADR 0011): never do a coordinated write on the main thread while a `StudioUIDocument` presents the file (it deadlocks), and do not rely on the `UIDocument` subclass being `Sendable` (Swift 6.4 saw the conformance inconsistently across files); pass `ObjectIdentifier`s. Untitled recovery (ADR 0012) lives in the app's `Library/Application Support/GamaStudio Recovery/`, keyed by the scene session; a simulator's data container moves on every reinstall, so re-read it with `simctl get_app_container` after each install. Measured on the iPhone simulator: swiping the app away keeps the scene session, so recovery survives it (ADR 0014). An explicit `--recovery-key` never adopts orphans unless `--adopt-orphans` is passed, so gate and developer leftovers are not picked up. The export picker's "Keep Both" returns the destination *folder*, not the file (measured on iOS 27.2, ADR 0019): never adopt a picked URL without `ExportedFile.resolve`, because adopting makes it the current file and deletes the Untitled recovery. The gate cannot drive the picker; re-measure by hand in a simulator with an existing `Untitled.usda` in On My iPhone.
- Graphs (ADR 0007) are document state; a graph affects the scene only through `EvaluateGraph`'s ordinary `SetComponent`s, bundled into the same transaction as the graph edit by `StudioModel.editGraph`. Never give a node definition or the evaluator another way to mutate.
- The command console (`GamaConsole`, ADR 0006) must never gain its own mutation path: a verb parses to an existing `DocumentCommand` or to a `StudioModel` method the toolbar already calls, and `ConsoleParserTests` compares each against the direct command.
- USD persistence is Gama's own stdlib-only USDA codec (`GamaUSD`), not `Entity.write` or ModelIO; `gama:` attributes are authoritative on read, and a format change means regenerating both fixtures in `Tests/GamaUSDTests/Fixtures` (ADR 0005).
- Agent shells may set `noclobber`: truncate with `>|`, and verify file edits by grepping for a marker rather than trusting an exit code.
