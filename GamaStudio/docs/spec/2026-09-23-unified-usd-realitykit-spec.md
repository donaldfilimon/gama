# Gama 3D — Unified USD / RealityKit / Swift Authoring Platform Specification

**Status:** Architecture and implementation specification  
**Target:** Swift 6.4+, modern Xcode, macOS-first with a cross-platform-capable core  
**Primary UI:** SwiftUI  
**Runtime:** RealityKit  
**Scene interchange / persistence boundary:** OpenUSD / USDZ  
**Cloud synchronization:** CloudKit  
**AI layer:** Foundation Models / Core AI where available, with provider abstraction  
**GPU / compute:** Metal-first abstraction with room for WebGPU, Vulkan, CUDA, and CPU SIMD backends  
**Product concept:** A Swift-native 3D authoring IDE and procedural scene environment, not merely a RealityKit viewport

---

## 1. Executive Summary

Gama should be designed as a **scene-authoring operating environment** whose UI is implemented with SwiftUI and whose Apple runtime projection is implemented with RealityKit.

The critical architectural distinction is:

> Gama is not a SwiftUI application with a RealityKit viewport. Gama is a document-centric 3D authoring platform whose UI, renderer, graph systems, AI, persistence, collaboration, and plugins all operate against a shared authoring model.

The architecture is built around five invariants:

1. **USD is the persistence and interchange boundary.**
2. **GamaCore owns authoring semantics.**
3. **RealityKit is a runtime/rendering projection, not the canonical database.**
4. **Every mutation is represented as an undoable command.**
5. **AI, UI, graphs, scripts, plugins, and collaboration all use the same command infrastructure.**

This enables a single scene to support:

- hierarchical scene authoring
- OpenUSD
- USDZ
- RealityKit
- Reality Composer compatibility
- procedural geometry
- material graphs
- animation graphs
- skeletons and IK
- physics
- particles
- GPU compute
- spatial audio
- cameras and lighting
- asset management
- AI-assisted scene authoring
- natural-language scene commands
- CloudKit synchronization
- offline editing
- collaboration
- plugin extensions
- diagnostics
- scripting
- import/export
- scene diffing
- version history
- platform-specific runtime projections

---

# 2. Product Vision

Gama should feel like a combination of:

- a 3D scene editor
- a procedural modeling environment
- a node-based programming system
- a USD authoring environment
- a material editor
- an animation workstation
- a physics/compute environment
- an AI-assisted creative IDE
- a collaborative document editor

The user should be able to accomplish the same operation through multiple interfaces.

For example:

### Direct manipulation

Move an object with a gizmo.

### Inspector

Set:

```text
Position X = 2.5
```

### Node graph

Connect a transform node.

### Command console

```text
move selected 2.5 0 0
```

### AI

```text
Move this object 2.5 meters to the right.
```

All of these must ultimately produce the same semantic operation:

```text
SetTransformCommand
```

This is the core unification principle of Gama.

---

# 3. High-Level Architecture

```text
                              GAMA
                               │
                ┌──────────────┴──────────────┐
                │                             │
             GamaUI                        GamaCore
                │                             │
      ┌─────────┼──────────┐        ┌─────────┼─────────┐
      │         │          │        │         │         │
  SwiftUI    Viewport    Editors   Scene    Commands  Graphs
      │         │          │        │         │         │
      └─────────┴──────────┴────────┴─────────┴─────────┘
                               │
                         GamaDocument
                               │
                 ┌─────────────┼─────────────┐
                 │             │             │
               USD          Components     Assets
                 │             │             │
                 └─────────────┼─────────────┘
                               │
                      Gama Runtime Bridge
                               │
             ┌─────────────────┼─────────────────┐
             │                 │                 │
         RealityKit          Metal          Compute
             │                 │                 │
             └─────────────────┼─────────────────┘
                               │
                     Apple Spatial Runtime
```

Supporting subsystems:

```text
GamaCore
   │
   ├── GamaUSD
   ├── GamaGraph
   ├── GamaGeometry
   ├── GamaMaterials
   ├── GamaAnimation
   ├── GamaPhysics
   ├── GamaAudio
   ├── GamaCompute
   ├── GamaAI
   ├── GamaCloud
   ├── GamaPlugins
   └── GamaDiagnostics
```

No subsystem should own the entire application.

`GamaCore` coordinates the document and command model.

---

# 4. Proposed Module Structure

```text
Gama/
├── GamaApp/
│   ├── Gama3DEditorApp.swift
│   └── ContentView.swift
│
├── GamaCore/
│   ├── GamaApplication.swift
│   ├── GamaDocument.swift
│   ├── GamaEntity.swift
│   ├── Components/
│   ├── Commands/
│   ├── Selection/
│   ├── Transactions/
│   └── History/
│
├── GamaUSD/
│   ├── USDDocument.swift
│   ├── USDStage.swift
│   ├── USDLayer.swift
│   ├── USDPrim.swift
│   ├── USDComposition.swift
│   └── USDExport.swift
│
├── GamaReality/
│   ├── RealityBridge.swift
│   ├── EntityRegistry.swift
│   ├── ViewportController.swift
│   ├── CameraController.swift
│   └── Gizmos/
│
├── GamaGraph/
│   ├── Graph.swift
│   ├── GraphNode.swift
│   ├── GraphPort.swift
│   ├── GraphConnection.swift
│   └── GraphEvaluator.swift
│
├── GamaGeometry/
├── GamaMaterials/
├── GamaAnimation/
├── GamaPhysics/
├── GamaAudio/
├── GamaCompute/
├── GamaAI/
├── GamaCloud/
├── GamaPlugins/
└── GamaDiagnostics/
```

For rapid prototyping, all of this can initially live in one `ContentView.swift`, separated by `// MARK:` sections and designed for later extraction.

---

# 5. Canonical Data Model

The original monolithic model:

```text
SceneDocument
    └── [SceneNode]
```

should evolve into:

```text
GamaDocument
 │
 ├── metadata
 ├── stage
 ├── layers
 ├── entities
 ├── components
 ├── graphs
 ├── animations
 ├── materials
 ├── assets
 ├── cameras
 ├── lights
 ├── physics
 ├── audio
 ├── variants
 ├── references
 └── editor metadata
```

An entity is primarily an identity.

```swift
struct GamaEntityID: Hashable, Codable, Sendable {
    let rawValue: UUID
}
```

A transform is a component:

```swift
struct TransformComponent: Codable, Sendable {
    var position: SIMD3<Float>
    var rotation: simd_quatf
    var scale: SIMD3<Float>
}
```

A mesh:

```swift
struct MeshComponent: Codable, Sendable {
    var assetID: GamaAssetID?
    var primitive: PrimitiveType?
}
```

A material:

```swift
struct MaterialComponent: Codable, Sendable {
    var materialID: GamaMaterialID?
}
```

Visibility:

```swift
struct VisibilityComponent: Codable, Sendable {
    var visible: Bool
    var locked: Bool
}
```

A character can therefore contain:

```text
Character
 ├── TransformComponent
 ├── MeshComponent
 ├── MaterialComponent
 ├── SkeletonComponent
 ├── AnimationComponent
 ├── PhysicsComponent
 ├── AudioComponent
 └── AIIdentityComponent
```

A light:

```text
KeyLight
 ├── TransformComponent
 ├── LightComponent
 └── VisibilityComponent
```

A camera:

```text
Camera
 ├── TransformComponent
 └── CameraComponent
```

---

# 6. Three Canonical Representations

Every important object should have three related representations:

```text
              AUTHORING
                  │
             GamaEntity
                  │
          ┌───────┴────────┐
          ▼                ▼
         USD             GRAPH
          │                │
          └───────┬────────┘
                  ▼
               RUNTIME
                  │
              RealityKit
```

Potential GPU projection:

```text
              Runtime
                 │
          ┌──────┴───────┐
          ▼              ▼
      RealityKit       GPU
                       │
                Metal / Compute
```

The renderer is a projection of the authored scene.

It is not the source of truth.

---

# 7. USD as Persistence Boundary

The persistent architecture is:

```text
GamaDocument
      │
      ▼
USDStage
      │
      ├── Root Layer
      ├── Sublayers
      ├── References
      ├── Payloads
      ├── Variants
      └── Prims
```

Every authoring object should have a bidirectional mapping:

```text
GamaEntityID
       ↕
USDPrimPath
       ↕
RealityKit Entity
```

Example:

```text
GamaEntityID:
4A9...

USD:
/World/Characters/Justine

RealityKit:
Entity(...)
```

This permits:

```text
Viewport selection
       ↓
RealityKit Entity
       ↓
GamaEntityID
       ↓
USD Prim
       ↓
Inspector
```

And:

```text
USD Prim
   ↓
GamaEntityID
   ↓
RealityKit Entity
   ↓
Viewport highlight
```

---

# 8. USD Layer Stack

Gama should expose USD composition directly.

Example:

```text
Scene.usda
│
├── Environment.usda
├── Characters.usda
├── Lighting.usda
├── Animation.usda
└── Overrides.usda
```

Layer panel:

```text
LAYERS

● Scene.usda
  ├─ Environment.usda
  ├─ Characters.usda
  ├─ Lighting.usda
  └─ Overrides.usda
```

Operations:

```text
New Layer
Duplicate
Mute
Solo
Move Up
Move Down
Merge
Export
Reload
Inspect
```

The layer system should support non-destructive authoring and composition inspection.

---

# 9. USD Prim Inspector

A professional USD inspector should expose:

```text
/World/Characters/Justine

Type
  Xform

Composition
  Reference
  Layer: Characters.usda

Transform
  xformOp:translate
  xformOp:rotateXYZ
  xformOp:scale

Attributes
  visibility
  purpose

Relationships
  material:binding

Variants
  Clothing
    Casual
    Formal
    Armor

Metadata
  customData
```

A raw USD view should also exist:

```text
PRIM

def Xform "Justine"
{
    float3 xformOp:translate = ...
    float3 xformOp:scale = ...
}
```

The exact syntax/API used by the implementation must follow the current Apple/OpenUSD APIs supported by the target SDK.

---

# 10. RealityKit Bridge

RealityKit should be incrementally synchronized.

```swift
@MainActor
final class RealityBridge {

    private var entityMap:
        [GamaEntityID: Entity] = [:]

    func create(
        entity: GamaEntity
    ) throws -> Entity

    func update(
        entity: GamaEntity
    ) throws

    func destroy(
        id: GamaEntityID
    )

    func synchronize(
        change: SceneChange
    ) throws
}
```

Changes:

```swift
enum SceneChange {
    case entityCreated(GamaEntityID)
    case entityDeleted(GamaEntityID)
    case componentAdded(GamaEntityID, Component)
    case componentChanged(GamaEntityID, Component)
    case componentRemoved(GamaEntityID, Component)
}
```

The bridge must update only the affected runtime objects.

Never rebuild the entire RealityKit scene for a small property change.

---

# 11. Command Architecture

Every mutation becomes a command.

```swift
protocol GamaCommand {

    var id: UUID { get }

    func validate(
        _ context: CommandContext
    ) throws

    func execute(
        _ context: CommandContext
    ) async throws

    func undo(
        _ context: CommandContext
    ) async throws
}
```

Commands should include:

```text
CreateEntityCommand
DeleteEntityCommand
DuplicateEntityCommand
SetTransformCommand
SetMaterialCommand
CreatePrimCommand
DeletePrimCommand
AddComponentCommand
RemoveComponentCommand
ConnectGraphCommand
DisconnectGraphCommand
CreateLayerCommand
MoveLayerCommand
ImportAssetCommand
ExportSceneCommand
CreateVariantCommand
SetVariantCommand
```

Commands should be:

- validated
- undoable
- serializable where appropriate
- auditable
- optionally synchronized
- usable by AI
- usable by scripts
- usable by plugins

---

# 12. Transaction System

Multiple commands should be grouped atomically.

```swift
try await editor.transaction {
    try await editor.execute(
        SetTransformCommand(...)
    )

    try await editor.execute(
        SetMaterialCommand(...)
    )

    try await editor.execute(
        AddComponentCommand(...)
    )
}
```

Failure should roll back the transaction.

```text
command 1 ✓
command 2 ✓
command 3 ✗

      ↓

ROLLBACK
```

This prevents partially applied procedural or AI operations.

---

# 13. Undo / Redo

History should be command-based rather than whole-scene snapshots.

```text
Create Sphere
Set Position
Set Material
Duplicate
Set Scale
```

Undo:

```text
Set Scale
```

Redo:

```text
Set Scale
```

This also creates a natural basis for:

- CloudKit change journals
- scene history
- collaboration
- branching
- audit logs
- AI change review

---

# 14. Selection System

Selection should support multiple semantic modes.

```swift
@Observable
final class SelectionState {

    var selected:
        Set<GamaEntityID> = []

    var primary:
        GamaEntityID?

    var mode:
        SelectionMode = .object
}
```

Modes:

```text
Object
Face
Edge
Vertex
Bone
Node
Material
Light
Camera
```

Operations:

```text
Select
Add
Subtract
Invert
Select Children
Select Parent
Select Similar
Select Material
Select Type
```

---

# 15. Transform Gizmos

The viewport should provide professional transform tools.

Move:

```text
X
Y
Z
XY
XZ
YZ
```

Rotate:

```text
X
Y
Z
Trackball
```

Scale:

```text
X
Y
Z
Uniform
```

Additional options:

```text
World / Local
Pivot / Origin
Snap
Increment
Surface Snapping
Vertex Snapping
Angle Snapping
```

Gizmos must be a tool subsystem rather than code embedded directly in the viewport.

---

# 16. Camera System

Camera manager:

```text
CAMERAS

Perspective
  Main

Perspective
  Character Closeup

Orthographic
  Front

Orthographic
  Side

Cinematic
  Shot 01
```

Parameters:

```text
FOV
Focal Length
Near Clip
Far Clip
Focus Distance
Aperture
Exposure
Transform
```

Camera bookmarks should be available through keyboard shortcuts and the UI.

---

# 17. Lighting System

Supported conceptual light types:

```text
Directional
Point
Spot
Area
Environment
Image-Based
```

Parameters:

```text
Intensity
Color
Temperature
Range
Cone Angle
Shadow
Exposure
```

Viewport visualization modes:

```text
Normal
Albedo
Lighting
Shadow
Wireframe
Bounds
```

---

# 18. Typed Graph System

The graph system should be generic.

```swift
enum PortType {
    case float
    case vector2
    case vector3
    case vector4
    case color
    case boolean
    case integer
    case string
    case texture
    case mesh
    case material
    case transform
    case entity
    case execution
    case custom(String)
}
```

Graph model:

```text
GraphDocument
 ├── GraphNode
 ├── GraphPort
 ├── GraphConnection
 └── GraphMetadata
```

Graphs should support:

```text
Geometry
Material
Animation
Physics
Particle
Compute
Logic
Scene
Audio
AI
```

The graph editor is one reusable framework rather than a collection of unrelated editors.

---

# 19. Material Graph

Example:

```text
             Texture
                │
                ▼
           ┌──────────┐
           │ Multiply │
           └────┬─────┘
                │
Color ──────────┤
                ▼
          Base Material
```

Nodes:

```text
Texture
Color
UV
Normal
Position
Time
Noise
Voronoi
Gradient
Math
Mix
Multiply
Add
Subtract
Power
Fresnel
Mask
PBR
Output
```

Material channels:

```text
Base Color
Metallic
Roughness
Normal
Emission
Opacity
Transmission
```

The graph should compile into the appropriate runtime material representation.

---

# 20. Procedural Geometry

Geometry graphs should remain editable.

Example:

```text
Cube
 │
 ▼
Subdivision
 │
 ▼
Noise
 │
 ▼
Displace
 │
 ▼
Bevel
 │
 ▼
Smooth
 │
 ▼
Material
 │
 ▼
Output
```

Geometry node families:

```text
Primitive
Transform
Mirror
Array
Scatter
Curve
Sweep
Loft
Extrude
Inset
Bevel
Boolean
Subdivide
Remesh
Smooth
Decimate
Displace
Noise
Instance
Join
Separate
```

---

# 21. Geometry Kernel

Do not make procedural geometry dependent on RealityKit.

```swift
protocol GeometryKernel {

    func generate(
        graph: GeometryGraph
    ) async throws -> MeshData
}
```

Potential backends:

```text
CPU SIMD
Metal
WebGPU
Vulkan
CUDA
```

RealityKit consumes the generated mesh representation.

This preserves portability.

---

# 22. Animation System

Animation should include both a timeline and graph-based state logic.

```text
Animation Graph
       │
       ├── State Machine
       ├── Blend Tree
       ├── Constraints
       ├── IK
       └── Timeline
```

Example:

```text
                 ┌── Idle
                 │
Input Speed ─────┼── Walk
                 │
                 └── Run
```

Parameters:

```text
speed
direction
grounded
jump
attack
emotion
```

---

# 23. Skeleton Editor

Hierarchy:

```text
Skeleton
 └── Root
      ├── Spine
      │    ├── Chest
      │    │    ├── Neck
      │    │    │    └── Head
      │    │    ├── LeftArm
      │    │    └── RightArm
      │    └── ...
      ├── LeftLeg
      └── RightLeg
```

Tools:

```text
Add Bone
Extrude
Reparent
Mirror
Orient
Bind
Paint Weights
Normalize
IK
Constraints
```

---

# 24. Physics Graph

Physics should be represented as structured components and graph relationships.

Rigid body:

```text
Mass
Friction
Restitution
Gravity
Damping
```

Collision shapes:

```text
Box
Sphere
Capsule
Convex
Mesh
```

Joints:

```text
Fixed
Hinge
Ball
Slider
Distance
```

---

# 25. Compute Graph

A first-class compute system should support:

```text
Input
 ↓
Spawn
 ↓
Initialize
 ↓
Force
 ↓
Noise
 ↓
Collision
 ↓
Integrate
 ↓
Output
```

Potential applications:

```text
Particles
Smoke
Fire
Rain
Snow
Crowds
Procedural Animation
GPU Geometry
Simulation
```

Metal should be the initial Apple-native backend.

---

# 26. Timeline

Timeline view:

```text
TIME  0       24       48       72

Camera ───────●────────────────●────

Character
Position ─────●──────●──────────●────

Rotation ─────────●──────────────●───

Material ─────────────●──────────────

Audio ────────────────████████████───
```

Features:

```text
Keyframes
Curves
Markers
Clips
Events
Dope Sheet
Graph Editor
Frame stepping
Loop regions
Playback
```

---

# 27. Asset Browser

Project organization:

```text
PROJECT

Scenes
Meshes
Materials
Textures
Animations
Characters
Audio
USD
USDZ
Reality
HDRI
Plugins
```

Asset metadata:

```text
Size
Dependencies
Triangles
Materials
Textures
Animations
Bounds
Memory Estimate
Source
Revision
```

Drag and drop:

```text
Asset → Viewport
Asset → Hierarchy
Asset → Graph
Texture → Material
Animation → Character
```

---

# 28. USD References

Example:

```text
Environment.usda
Character.usda
```

Referenced by:

```text
MainScene.usda
    ├── reference Environment
    └── reference Character
```

The editor should display:

```text
Character
  ↳ Reference
      Character.usda
```

Actions:

```text
Open Source
Break Reference
Reload
Override
Inspect
```

---

# 29. USD Variants

Variants should be first-class UI features.

Example:

```text
CHARACTER

Outfit
 ├── Casual
 ├── Formal
 └── Armor

Hair
 ├── Short
 ├── Long
 └── Ponytail
```

Switching variants should preserve the underlying source asset.

---

# 30. AI Architecture

AI must never bypass the authoring system.

Correct architecture:

```text
Natural Language
       ↓
Scene Understanding
       ↓
Structured Intent
       ↓
Command Planner
       ↓
Validation
       ↓
Editor Commands
       ↓
USD
       ↓
RealityKit
```

Incorrect architecture:

```text
LLM
 ↓
random direct RealityKit mutations
```

The AI layer should understand:

```text
Scene
Hierarchy
USD
Components
Graphs
Materials
Animations
Assets
Cameras
Lighting
Physics
```

---

# 31. AI Change Preview

Before applying AI changes:

```text
AI PROPOSAL

3 changes

✓ Increase key light intensity
✓ Move camera 0.8m closer
✓ Reduce environment exposure

[Preview] [Apply] [Cancel]
```

For larger operations:

```text
This operation modifies 17 prims.

[Review Changes]
[Apply]
[Cancel]
```

AI actions should produce the same commands that a human editor operation would produce.

---

# 32. AI Procedural Modeling

Prompt:

```text
Create a stylized sci-fi desk.
```

Potential generated authoring structure:

```text
Desk
 ├── Top
 ├── Legs
 ├── Supports
 ├── Monitor
 ├── Keyboard
 └── Lighting
```

The result should remain editable.

Prefer:

```text
Prompt
 ↓
Procedural Graph
 ↓
USD
 ↓
Runtime
```

over:

```text
Prompt
 ↓
opaque baked mesh
```

---

# 33. AI Scene Search

Natural-language queries:

```text
Show me all metallic objects.

Which meshes have no material?

Find unused textures.

Where is the main camera?

Which characters have animations?

Show objects referenced from another USD file.
```

This can eventually be backed by a semantic scene index.

---

# 34. Command Console

A live command console should exist inside the editor.

Examples:

```text
add sphere
```

```text
move sphere 0 1 0
```

```text
metallic 0.8
```

```text
duplicate selected
```

```text
export usdz
```

```text
find all untextured meshes
```

The console should parse commands into the same command bus.

---

# 35. CloudKit Architecture

Do not synchronize RealityKit entities.

Synchronize document changes.

```text
Local Scene
     ↓
Change Journal
     ↓
CloudKit
     ↓
Change Journal
     ↓
Remote Scene
```

Conceptual change record:

```swift
struct SceneChange: Codable, Sendable {

    let id: UUID
    let documentID: UUID
    let authorID: String
    let timestamp: Date

    let primPath: String
    let operation: Operation
    let payload: Data

    let baseRevision: UInt64
}
```

This supports:

```text
Offline editing
Multi-device editing
History
Conflict detection
Rollback
Branching
```

CloudKit should synchronize authoring state and collaboration metadata, not frame-by-frame renderer state.

---

# 36. Collaboration

Potential collaborative state:

```text
Donald
 └── /World/Character

User B
 └── /World/Environment

User C
 └── /World/Lighting
```

Presence:

```text
● Donald
● User B
● User C
```

Remote selection:

```text
/World/Character
   ↑
Donald
```

Conflict handling should be explicit and deterministic.

---

# 37. Plugin Architecture

Conceptual interface:

```swift
protocol GamaPlugin {

    var identifier: String { get }
    var name: String { get }
    var version: String { get }

    func register(
        with registry: PluginRegistry
    )
}
```

Plugins may register:

```text
Commands
Nodes
Importers
Exporters
Inspectors
Tools
Materials
Validators
AI Providers
Simulation Systems
```

Potential plugins:

```text
RealityComposerPlugin
USDPlugin
BlenderImportPlugin
GLTFPlugin
AIModelPlugin
AnimationPlugin
```

Plugin APIs must remain capability-scoped and sandboxable.

---

# 38. Reality Composer Compatibility

A dedicated compatibility layer:

```text
GamaRealityComposerPlugin
```

Conceptual pipeline:

```text
Reality Asset
      ↓
Parser
      ↓
Entity Mapping
      ↓
Component Mapping
      ↓
Graph Mapping
      ↓
Gama Scene
      ↓
USD
```

Reverse export should be supported where the destination format has equivalent semantics:

```text
Gama Scene
      ↓
USD
      ↓
RealityKit
      ↓
Runtime
```

Compatibility should be based on explicit semantic mappings rather than assuming all Reality Composer data has a one-to-one equivalent.

---

# 39. Project / Document Format

Potential project types:

```text
.gama
.usda
.usdc
.usdz
.reality
```

A `.gama` project can conceptually contain:

```text
MyProject.gama/
    Project.json
    Scene.usda
    Layers/
    Assets/
    Graphs/
    Animations/
    Metadata/
```

USD remains the authoritative scene representation inside the project.

---

# 40. Autosave and Recovery

Use a journal-based autosave model.

```text
User Edit
   ↓
Command
   ↓
Journal
   ↓
Periodic Snapshot
```

Recovery:

```text
Snapshot
   +
Pending Journal
   ↓
Recovery
```

This reduces corruption risk and provides a natural basis for history and collaboration.

---

# 41. Diagnostics

Dedicated diagnostics panel:

```text
GAMA DIAGNOSTICS

Scene
  14,218 prims
  82 meshes
  21 materials

GPU
  4.2 ms

CPU
  2.8 ms

Memory
  1.4 GB

Textures
  742 MB

Warnings
  2

Errors
  0
```

Warnings can include:

```text
Texture exceeds recommended resolution
Unused material
Missing USD reference
Non-uniform scale
High triangle count
Unoptimized instance
```

Diagnostics should be actionable where possible.

---

# 42. Performance Architecture

Do not make SwiftUI observable state equal the renderer's complete state.

Separate:

```text
Authoring State
Runtime State
Derived State
UI State
```

Pipeline:

```text
SceneDocument
     ↓
DerivedSceneCache
     ↓
RealityKit
```

SwiftUI observes authoring state and relevant derived state.

The renderer observes targeted changes.

This prevents unnecessary SwiftUI invalidation and complete scene rebuilds.

---

# 43. Concurrency Architecture

Use Swift concurrency deliberately.

Potential isolation:

```text
@MainActor
EditorController

actor USDActor

actor AssetDatabase

actor ImportPipeline

actor GraphEvaluator

actor CloudSync

actor AIEngine
```

Heavy processing should stay off the UI actor:

```text
USD parsing
Mesh generation
Thumbnail generation
Texture processing
Graph compilation
AI requests
CloudKit synchronization
```

RealityKit mutations must respect the actor/threading requirements of the targeted SDK.

No global mutable state.

No giant singleton.

No renderer-owned database.

---

# 44. Swift 6 Concurrency Requirements

The codebase should be designed for:

```text
Sendable
actor
@MainActor
nonisolated
async/await
Observation
strict concurrency
```

from the beginning.

Avoid adding concurrency after the architecture has already become stateful and globally mutable.

---

# 45. Application Root

The composition root should be intentionally small.

```swift
import SwiftUI

struct ContentView: View {

    @State private var app =
        GamaApplication()

    var body: some View {
        GamaEditorShell(
            application: app
        )
        .environment(app)
    }
}
```

Conceptual application object:

```swift
@Observable
@MainActor
final class GamaApplication {

    let document: GamaDocument
    let selection: SelectionState
    let commands: CommandStore
    let viewport: ViewportController
    let undoManager: GamaUndoManager
    let collaboration: CollaborationController
    let intelligence: SceneIntelligence
}
```

---

# 46. Editor Shell

The complete editor composition should be:

```text
ContentView
    ↓
GamaEditorShell
    ├── EditorToolbar
    ├── SceneHierarchy
    ├── RealityViewport
    ├── NodeEditor
    ├── Inspector
    ├── Timeline
    ├── AssetBrowser
    ├── Console
    └── StatusBar
```

Additional panels:

```text
Layers
Materials
Animation
Physics
Skeleton
Diagnostics
AI Assistant
History
Collaboration
```

Panels should be detachable/dockable in the mature application.

---

# 47. Viewport

The viewport should eventually support:

```text
Perspective
Orthographic
Camera View
Frame Selected
Frame All
Orbit
Pan
Zoom
Fly
Walk
Dolly
Focus
```

Interaction:

```text
Select
Marquee
Transform
Rotate
Scale
Measure
Annotate
Paint
Sculpt
```

Viewport overlays:

```text
Grid
Axes
Bounds
Wireframe
Normals
Skeleton
Physics
Lights
Cameras
Selection
Performance
```

---

# 48. Scene Hierarchy

Hierarchy should display:

```text
WORLD
 ├── Environment
 │    ├── Ground
 │    ├── Sky
 │    └── Lighting
 │
 ├── Characters
 │    └── Justine
 │         ├── Body
 │         ├── Hair
 │         └── Accessories
 │
 └── Cameras
      └── MainCamera
```

Actions:

```text
Create
Delete
Duplicate
Rename
Reparent
Group
Ungroup
Hide
Lock
Isolate
Search
Filter
```

---

# 49. Inspector

Inspector sections:

```text
Identity
Transform
Hierarchy
Mesh
Material
Lighting
Animation
Physics
Audio
Components
USD
Variants
References
Metadata
Diagnostics
```

Transform editor:

```text
Position
Rotation
Scale
Pivot
```

Material editor:

```text
Base Color
Metallic
Roughness
Normal
Emission
Opacity
```

Advanced users can switch to raw USD/property inspection.

---

# 50. Asset and Dependency Graph

The editor should eventually expose dependency relationships:

```text
Character.usda
      │
      ├── Body.usd
      ├── Hair.usd
      ├── SkinMaterial.usda
      ├── HairTexture.png
      └── Walk.anim
```

This enables:

```text
Find dependents
Find dependencies
Find unused assets
Reload dependencies
Replace asset
Relink
```

---

# 51. Scene Validation

Validation should operate before export and optionally continuously.

Rules:

```text
Missing references
Invalid prim paths
Missing materials
Unsupported assets
Invalid transforms
Broken graph connections
Cycles where prohibited
Missing animation targets
Physics inconsistencies
Unsupported RealityKit mappings
Texture problems
Performance warnings
```

Result:

```text
Validation

✓ USD composition
✓ References
✓ Materials
⚠ 2 unused textures
⚠ 1 non-uniform scale
✓ Animation
✓ Physics
✓ Export compatibility
```

---

# 52. Scene Diff

Because the document is structured, Gama can expose a semantic diff.

Example:

```text
SCENE DIFF

/World/Character
  Transform.position.x
    1.0 → 2.5

/World/Character/Hair
  Material
    HairDark → HairChestnut

/World/Lighting/Key
  intensity
    500 → 800
```

This is useful for:

- version history
- collaboration
- AI review
- debugging
- source control
- CloudKit conflict resolution

---

# 53. Branching

Eventually:

```text
main
 │
 ├── lighting-experiment
 ├── character-v2
 └── environment-rebuild
```

Branches can be implemented above the command/change journal layer rather than duplicating massive scene files.

---

# 54. AI + Command Security

AI should operate under capability restrictions.

Example capabilities:

```text
read.scene
read.assets
read.usd
modify.scene
modify.materials
modify.animation
export.scene
run.procedural
network.access
cloud.write
```

An AI request should be evaluated against granted capabilities.

For example:

```text
AI wants to modify 42 prims.

Capability:
modify.scene = allowed

Validation:
passed

Preview:
required

Apply:
user confirmed
```

This prevents an AI provider from having unrestricted access to the entire document.

---

# 55. AI Understanding Pipeline

The AI layer should distinguish:

```text
Observed Fact
Evidence
Derived State
Inference
Generated Proposal
```

For example:

```text
Observed:
Object has no material.

Derived:
Renderer will use fallback material.

Proposal:
Assign a metallic gray material.
```

The proposal should not be silently treated as fact.

---

# 56. Natural Language Scene Commands

Examples:

```text
Create a 2-meter sphere.
```

```text
Make the selected material metallic.
```

```text
Duplicate this character three times along X.
```

```text
Create a procedural staircase.
```

```text
Find every object using this texture.
```

```text
Show me objects with more than 100,000 triangles.
```

```text
Create a camera shot around the selected character.
```

All should resolve into structured intents and then commands.

---

# 57. Procedural Modeling AI

The long-term architecture:

```text
User Prompt
     ↓
Intent
     ↓
Semantic Model
     ↓
Procedural Graph
     ↓
Geometry Evaluation
     ↓
USD
     ↓
RealityKit
```

This is preferable to making AI output arbitrary geometry blobs.

The graph remains editable and explainable.

---

# 58. Gama as a 3D IDE

Gama should support an integrated project environment:

```text
PROJECT
 ├── Scenes
 ├── Assets
 ├── Materials
 ├── Graphs
 ├── Scripts
 ├── Plugins
 ├── Tests
 └── Exports
```

Developer mode:

```text
Scene
USD
Graph
Commands
Logs
Diagnostics
Runtime
```

Artist mode:

```text
Viewport
Hierarchy
Inspector
Materials
Animation
Assets
```

AI mode:

```text
Assistant
Scene Understanding
Command Preview
Generated Graphs
Validation
```

---

# 59. Command Bus as the Central Nervous System

The complete architecture becomes:

```text
                ┌──────────────┐
                │ SwiftUI UI   │
                └──────┬───────┘
                       │
                ┌──────▼───────┐
                │ Node Graph   │
                └──────┬───────┘
                       │
                ┌──────▼───────┐
                │ AI / Scripts │
                └──────┬───────┘
                       │
                       ▼
                ┌──────────────┐
                │ Command Bus  │
                └──────┬───────┘
                       │
             ┌─────────┼─────────┐
             ▼         ▼         ▼
            USD     Runtime    Undo
             │         │         │
             ▼         ▼         ▼
          Document  RealityKit History
                       │
                       ▼
                    Viewport
```

This is the key architecture to preserve during implementation.

---

# 60. Single-File Prototype Strategy

For rapid development, a complete prototype can initially live in:

```text
ContentView.swift
```

Use internal sections:

```swift
// MARK: App

// MARK: Application

// MARK: Document

// MARK: Entity

// MARK: Components

// MARK: Commands

// MARK: Transactions

// MARK: Selection

// MARK: USD

// MARK: RealityKit

// MARK: Viewport

// MARK: Gizmos

// MARK: Hierarchy

// MARK: Inspector

// MARK: Graph

// MARK: Timeline

// MARK: Assets

// MARK: AI

// MARK: CloudKit

// MARK: Diagnostics
```

The file should remain a composition root and working prototype rather than becoming the permanent monolith.

---

# 61. Recommended Initial Implementation Order

## Phase 0 — Foundation

Implement:

```text
GamaApplication
GamaDocument
GamaEntityID
Entity store
Component store
SelectionState
Command protocol
CommandStore
Undo/redo
```

Goal:

A reliable authoring model exists before sophisticated rendering is added.

---

## Phase 1 — RealityKit Runtime

Implement:

```text
RealityBridge
Entity registry
Primitive factory
Camera
Lighting
Transform synchronization
Selection highlighting
```

Goal:

Every document entity can be projected into RealityKit.

---

## Phase 2 — Editor

Implement:

```text
Hierarchy
Inspector
Viewport
Transform tools
Multi-selection
Search
Command console
```

Goal:

The application becomes genuinely usable.

---

## Phase 3 — USD

Implement:

```text
Stage abstraction
Prim mapping
Layer model
References
Variants
Attributes
Relationships
Import/export
USDZ pipeline
```

Goal:

The scene becomes persistent and interoperable.

Exact APIs should be implemented against the target Apple SDK/OpenUSD version rather than invented abstractions pretending to be current SDK signatures.

---

## Phase 4 — Graph Framework

Implement:

```text
GraphDocument
GraphNode
GraphPort
GraphConnection
Graph evaluator
Graph editor
```

Then specialize:

```text
Geometry
Material
Animation
Physics
Compute
Logic
```

---

## Phase 5 — Assets

Implement:

```text
Asset browser
Metadata
Dependency graph
Thumbnail generation
Import pipeline
Drag/drop
Relinking
Validation
```

---

## Phase 6 — Animation

Implement:

```text
Timeline
Keyframes
Curves
Animation clips
State machine
Blend tree
Skeleton
IK
```

---

## Phase 7 — Physics / Compute

Implement:

```text
Rigid bodies
Collision
Joints
Particles
Compute graphs
Metal kernels
```

---

## Phase 8 — AI

Implement:

```text
Scene index
Natural language parser
Structured intents
Command planner
Validation
Preview
Apply
AI procedural graphs
Natural language scene search
```

---

## Phase 9 — CloudKit

Implement:

```text
Change journal
Snapshots
Conflict detection
Offline queue
Remote synchronization
Presence
History
```

---

## Phase 10 — Plugins

Implement:

```text
Plugin registry
Capability system
Node registration
Command registration
Importer/exporter registration
Inspector extensions
```

---

# 62. Minimum Viable Gama

The first genuinely useful milestone should not attempt to implement everything.

It should provide:

```text
✓ SwiftUI editor shell
✓ RealityKit viewport
✓ Hierarchy
✓ Inspector
✓ Primitive creation
✓ Transform editing
✓ Selection
✓ Undo/redo
✓ Command bus
✓ Document model
✓ Basic USD abstraction
✓ Asset browser
✓ Basic node graph
✓ Save/load
```

Once those are solid, the rest can be layered onto the same architecture.

---

# 63. Full Gama Target

The mature product becomes:

```text
                         GAMA

                 Swift-Native 3D IDE
                         │
       ┌─────────────────┼─────────────────┐
       │                 │                 │
  Scene Authoring   Procedural Graphs   AI Authoring
       │                 │                 │
       └─────────────────┼─────────────────┘
                         │
                      GamaCore
                         │
       ┌─────────────────┼─────────────────┐
       │        │        │        │         │
      USD     Assets   Physics  Animation  Audio
       │        │        │        │         │
       └────────┴────────┴────────┴─────────┘
                         │
                  Runtime Projection
                         │
              ┌──────────┼──────────┐
              │          │          │
          RealityKit   Metal     Compute
              │          │          │
              └──────────┼──────────┘
                         │
                    Apple Runtime
```

---

# 64. Architectural Invariants

These rules should be treated as non-negotiable.

### Invariant 1

**RealityKit is not the canonical scene database.**

### Invariant 2

**USD is the persistence/interchange boundary.**

### Invariant 3

**UI does not directly mutate the scene.**

UI produces commands.

### Invariant 4

**AI does not directly mutate the scene.**

AI produces validated commands.

### Invariant 5

**Graphs do not bypass the document model.**

Graph evaluation produces structured scene changes.

### Invariant 6

**CloudKit does not synchronize renderer objects.**

It synchronizes document/change state.

### Invariant 7

**Undo/redo operates on semantic commands.**

### Invariant 8

**Long-running work does not block the UI actor.**

### Invariant 9

**Components remain independent of specific UI views.**

### Invariant 10

**The editor can replace its runtime projection without destroying the authoring model.**

---

# 65. Final Product Definition

Gama should ultimately be understood as:

> **A Swift-native, USD-first, AI-assisted 3D development environment for authoring scenes, procedural geometry, materials, animation, physics, compute, spatial content, and interactive experiences.**

Its major architectural pillars are:

```text
Swift 6+
    ↓
SwiftUI
    ↓
GamaCore
    ↓
Component / Command Architecture
    ↓
USD
    ↓
RealityKit
    ↓
Metal / Compute
```

with:

```text
AI
CloudKit
Plugins
Graphs
Assets
Diagnostics
Collaboration
```

operating as first-class systems around the same document model.

The most important design decision is therefore not a particular SwiftUI view, RealityKit API, or node type.

It is the separation:

```text
AUTHORING MODEL
      ≠
RUNTIME MODEL
      ≠
UI MODEL
      ≠
AI MODEL
```

with explicit bridges between them.

That separation is what allows Gama to grow from the current `ContentView.swift` prototype into a serious production-grade 3D IDE without having to rewrite the entire application when USD, procedural modeling, AI, CloudKit collaboration, or additional rendering backends are introduced.

---

# 66. Immediate Next Build Target

The next implementation should produce a working single-file prototype containing:

```text
GamaApplication
GamaDocument
GamaEntity
Component storage
SelectionState
CommandBus
Undo/Redo
Transactions
RealityBridge
ViewportController
Camera
Transform gizmos/state
Primitive factory
Hierarchy
Inspector
Typed graph model
Drag/drop graph nodes
Timeline model
Asset browser
Command console
USD document abstraction
AI command interface
CloudKit synchronization interfaces
Diagnostics
```

The implementation should prioritize **real working behavior over decorative UI**.

The resulting prototype should be structured so that each subsystem can later be extracted into:

```text
GamaCore
GamaUSD
GamaReality
GamaGraph
GamaGeometry
GamaMaterials
GamaAnimation
GamaPhysics
GamaCompute
GamaAI
GamaCloud
GamaPlugins
GamaDiagnostics
```

without changing the conceptual document model.

---

# 67. Final Architectural Statement

Gama is not intended to be another wrapper around RealityKit.

It should be the authoring layer that sits above the runtime.

```text
                 GAMA
                  │
        ┌─────────┴─────────┐
        │                   │
     Authoring           Intelligence
        │                   │
        ▼                   ▼
      GamaCore            GamaAI
        │                   │
        └─────────┬─────────┘
                  │
              Commands
                  │
                  ▼
               GamaDocument
                  │
        ┌─────────┼─────────┐
        ▼         ▼         ▼
       USD      Graphs    Assets
        │         │         │
        └─────────┼─────────┘
                  │
             Runtime Bridge
                  │
        ┌─────────┴─────────┐
        ▼                   ▼
    RealityKit           Metal/GPU
        │                   │
        └─────────┬─────────┘
                  ▼
            Apple Runtime
```

That architecture gives the project a durable center: **the document and command model**, rather than any one renderer, UI framework, AI provider, or platform API.
