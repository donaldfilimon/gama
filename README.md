# Gama Studio

Gama Studio is a Swift-native, document-centric 3D authoring app. The vision is in `docs/spec/2026-09-23-unified-usd-realitykit-spec.md`.

**Status: Phase 1.** The project has two parts:
- `GamaAuthoring` is a standard-library-only authoring core with a value document, undoable commands, atomic transactions, selection, and an incremental change feed.
- `GamaReality` projects it into RealityKit incrementally.

There is no viewport, UI, or USD support yet. See `AGENTS.md` for the gate and what comes next, and `docs/adr/` for decisions.

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
