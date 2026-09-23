# Gama Studio

Gama Studio is a Swift-native, document-centric 3D authoring app. The vision is in `docs/spec/2026-09-23-unified-usd-realitykit-spec.md`.

**Status: Phase 2.** macOS, plus iOS and visionOS apps (`Apps/GamaStudioApp`, ADR 0008). The project has six parts:
- `GamaAuthoring` is a standard-library-only authoring core with a value document, undoable commands, atomic transactions, selection, and an incremental change feed.
- `GamaReality` projects it into RealityKit incrementally.
- `GamaGraph` evaluates typed node graphs stored in the document; material and transform graphs drive the scene through the same undoable commands (ADR 0007).
- `GamaConsole` parses typed console commands into the same undoable edits (ADR 0006).
- `GamaUSD` saves and loads documents as USDA with an exact round trip, using standard USD schemas so other USD tools can open the files (ADR 0005).
- `GamaStudioEditor` + the `gama-studio` executable host both of those in an editor window built from Gama views (`donaldfilimon/gama`, pinned by revision to an unmerged PR — see `AGENTS.md`), around a RealityKit viewport with orbit/pan/zoom camera controls, a "Frame" toolbar button, click-to-select picking, and a wireframe highlight around the selection. See ADR 0003.

```bash
unset TOOLCHAINS
swiftly run swift run gama-studio
```

Cameras and lights are authored document components too — a camera never drives the viewport, and lights fall back to a fixed editor light only when the document has none of its own (ADR 0004). File ▸ Open/Save/Save As (⌘O, ⌘S, ⇧⌘S) read and write `.usda`; `gama-studio --open <file>` starts from one and `--export <file>` writes one without opening a window. On iOS and visionOS, toolbar Open/Save/Save As buttons (and ⌘O/⌘S/⇧⌘S on a hardware keyboard) use the system document picker (ADR 0009), `.usda` files open in Gama Studio from Files or other apps (ADR 0010), a document with a file autosaves in place and reloads when another app changes it (ADR 0011), and unsaved Untitled changes survive a relaunch (ADR 0012); recovery files of closed windows are offered to a new window, or removed after 7 days (ADR 0013, ADR 0014); the status line and the console say when changes were recovered (ADR 0015, ADR 0016), and the console keeps notes of opens, saves, autosaves, reloads, and refusals (ADR 0017). A Console panel above the status line takes typed commands (`add sphere`, `move selected 0 1 0`, `metallic 0.8`, `help`) and runs them as the same undoable edits the panels make (ADR 0006). The toolbar's "Graph" toggle swaps the inspector for a graph editor (ADR 0007). See `AGENTS.md` for the gate and what comes next, and `docs/adr/` for decisions.

```swift
import GamaAuthoring

var session = EditorSession()
let sphere = session.document.nextEntityID
try session.execute(CreateEntity(name: "Sphere", components: [.transform(.identity), .mesh(.sphere)]))
try session.execute(SetComponent(sphere, .transform(Transform(position: SIMD3(2.5, 0, 0)))))
try session.undo()        // back to the origin

let bridge = RealityBridge()           // import GamaReality (Apple platforms)
bridge.rebuild(from: session.document) // once, when a document opens
try session.redo()
bridge.apply(session.drainChanges(), from: session.document)  // after every edit
// add bridge.root to a RealityView or ARView scene
```
