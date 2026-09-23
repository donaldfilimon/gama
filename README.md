# Gama Studio

Gama Studio is a Swift-native, document-centric 3D authoring app. The vision is in `docs/spec/2026-09-23-unified-usd-realitykit-spec.md`.

**Status: Phase 2.** macOS only. The project has three parts:
- `GamaAuthoring` is a standard-library-only authoring core with a value document, undoable commands, atomic transactions, selection, and an incremental change feed.
- `GamaReality` projects it into RealityKit incrementally.
- `GamaStudioEditor` + the `gama-studio` executable host both of those in an editor window built from Gama views (`donaldfilimon/gama`, pinned by revision to an unmerged PR — see `AGENTS.md`), around a RealityKit viewport with orbit/pan/zoom camera controls, a "Frame" toolbar button, and click-to-select picking. See ADR 0003.

```bash
unset TOOLCHAINS
swiftly run swift run gama-studio
```

Cameras and lights are authored document components too — a camera never drives the viewport, and lights fall back to a fixed editor light only when the document has none of its own (ADR 0004). There is no USD support or command console yet. See `AGENTS.md` for the gate and what comes next, and `docs/adr/` for decisions.

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
