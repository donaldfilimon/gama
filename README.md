# Gama Studio

Gama Studio is a Swift-native, document-centric 3D authoring app. The vision is in `docs/spec/2026-09-23-unified-usd-realitykit-spec.md`.

**Status: Phase 0.** `GamaAuthoring` is a standard-library-only authoring core with a value document, undoable commands, atomic transactions, selection, and an incremental change feed. There is no renderer, UI, or USD support yet. See `AGENTS.md` for the gate and what comes next, and `docs/adr/` for decisions.

```swift
import GamaAuthoring

var session = EditorSession()
let sphere = session.document.nextEntityID
try session.execute(CreateEntity(name: "Sphere", components: [.transform(.identity), .mesh(.sphere)]))
try session.execute(SetComponent(sphere, .transform(Transform(position: SIMD3(2.5, 0, 0)))))
try session.undo()        // back to the origin
let changes = session.drainChanges()   // what a runtime projection would apply
```
