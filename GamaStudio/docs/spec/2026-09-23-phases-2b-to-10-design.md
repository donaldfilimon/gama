# Gama Studio: phases 2b to 10 design

Status: Proposed (2026-09-23). This is a design for building the rest of
`2026-09-23-unified-usd-realitykit-spec.md` (the vision spec). It is not a
capability claim. Nothing here exists until it has a target, passing tests,
and an ADR that records what was measured.

## 1. Why

Phases 0 to 2 of the vision spec (§61) are built and gated: the value
document and commands, the RealityKit projection, the editor shell, and the
touch hosts with file handling and recovery (ADRs 0001 to 0020). Phases 3
(USD) and 4 (Graph) are partial. Phases 5 to 10 are not started. Donald asked
on 2026-09-23 for the whole spec, in its order, with review after each part.

His decisions, recorded here so the plan argues from them:
- **Scope:** the whole spec in the spec's §61 order. The order is
  3 USD, 4 Graph, 5 Assets, 6 Animation, 7 Physics/Compute, 8 AI,
  9 CloudKit, 10 Plugins. A **Phase 2b** goes first because §62 (Minimum
  Viable Gama) still lacks transform editing tools and ADRs 0006 and 0011
  record console verbs and macOS autosave as not built.
- **Subsystems the local gate cannot prove** (CloudKit sync, model-backed
  AI): local-first. Each sits behind a protocol with a fully tested
  in-process implementation. CloudKit and Foundation Models are thin adapters
  in their own Apple-only targets, marked Provisional in the docs until proven
  on a signed device.
- **Platforms:** each phase lands on macOS (unit tests), iOS, and visionOS
  (builds, simulator smokes, hand checks) before the next starts.
- **Structure:** one spec (this file) and one implementation plan, executed
  by Subagent-Driven Development with a whole-phase review and one fix wave
  at every phase boundary.

## 2. Global constraints

These apply to every phase and every task.

- Repository: `~/dev/active/gama-studio`, commit on `main`, no remote.
  `Package.swift` stays `swift-tools-version: 6.4`; `.swift-version` stays
  `main-snapshot-2026-08-21`; the platform floor stays macOS 15 / iOS 18 /
  tvOS 26 / visionOS 2.
- The gama framework pin (`2ef325c`, an unmerged PR head) does not change,
  and no phase may need a new gama feature. Anything that would is a blocker
  to surface to Donald, not a task.
- `AGENTS.md` invariants 1 to 10 hold. In particular: every mutation is a
  `DocumentCommand` through `EditorSession`; every new command has a case in
  `CommandRoundTripTests.cases`; the RealityKit bridge stays read-only and
  `BridgeConvergenceTests` stay green; every panel and tool goes through
  `StudioModel`; main-actor crossings are explicit.
- Every new library target that holds a model or an evaluator is standard
  library only and is listed in the gate's import ban. Apple frameworks live
  in `GamaReality`, `GamaStudioEditor`, or a named adapter target.
- Gate: `./tools/check.sh >| log 2>&1; echo EXIT:$?`, green only on
  `check.sh: PASSED`. Test floors go up with every task and never down. The
  `ios and visionos` stage shares the iPhone 17 and Apple Vision Pro
  simulators with a peer session: a "free" handshake precedes every run.
- Each phase ends with an ADR numbered from 0021 upward (0019 belongs to the
  peer's Save As fix; numbers are claimed in order at phase start), recording
  what was measured, what was checked by hand on which simulator, and what
  was not built.
- Prose: no em dashes. Nothing is described as existing without a target and
  passing tests. The status vocabulary for adapters is: **Implemented**
  (tested in the gate), **Provisional** (compiles, exercised only by hand or
  not at all, named as such in the ADR and in `AGENTS.md`).
- Commit messages end with
  `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.

## 3. Module map

Names follow vision spec §4. `GamaAssets` is added because §4 names no
assets module while §27, §50, and §61 Phase 5 require one. Arrows are
SwiftPM dependencies; a target may only import what it depends on.

| Target | Kind | Depends on | Responsibility |
| --- | --- | --- | --- |
| `GamaAuthoring` | stdlib, exists | none | document, components, commands, session, selection, graphs; gains the components and composition records below |
| `GamaUSD` | stdlib, exists | GamaAuthoring | USDA codec; gains foreign prims, layers, references, variants, relationships, `.usdz` |
| `GamaGraph` | stdlib, exists | GamaAuthoring | evaluator and standard nodes; gains node families |
| `GamaConsole` | stdlib, exists | GamaAuthoring, GamaGraph | console parser; gains verbs per phase |
| `GamaGeometry` | stdlib, new | GamaAuthoring | mesh kernel, procedural generation |
| `GamaMaterials` | stdlib, new | GamaAuthoring, GamaGraph | material graph compilation to `MaterialDescription` |
| `GamaAssets` | stdlib, new | GamaAuthoring, GamaUSD | catalog, metadata, dependency graph, relinking, validation |
| `GamaAnimation` | stdlib, new | GamaAuthoring | timeline, curves, clips, state machine, blend tree, skeleton, IK, sampler |
| `GamaPhysics` | stdlib, new | GamaAuthoring | body, collider, joint, particle descriptions; deterministic CPU step |
| `GamaCompute` | stdlib, new | GamaAuthoring, GamaGraph | compute graph model; CPU evaluator |
| `GamaComputeMetal` | Apple, new | GamaCompute | Metal evaluator for the same graphs |
| `GamaAudio` | stdlib, new | GamaAuthoring | audio source semantics and validation |
| `GamaDiagnostics` | stdlib, new | GamaAuthoring, GamaAssets | diagnostics records, counters, validation report |
| `GamaAI` | stdlib, new | GamaAuthoring, GamaGraph, GamaGeometry, GamaAssets | scene index, intents, planner, policy, preview, search; `ModelBackend` protocol; deterministic backend |
| `GamaAIFoundation` | Apple, new | GamaAI | Foundation Models backend, `#available` macOS 26 / iOS 26 / visionOS 26; Provisional |
| `GamaCloud` | stdlib, new | GamaAuthoring | change journal, snapshots, conflicts, offline queue, presence, history; `SyncTransport` protocol; `MemoryTransport` |
| `GamaCloudKit` | Apple, new | GamaCloud | CloudKit transport; Provisional |
| `GamaPlugins` | stdlib, new | GamaAuthoring, GamaGraph, GamaConsole, GamaAssets | registry, capabilities, registrations |
| `GamaReality` | Apple, exists | GamaAuthoring, GamaGeometry, GamaMaterials, GamaAnimation, GamaPhysics, GamaAudio | projections; gains materials, meshes, physics, animation, particles, audio, gizmo entities |
| `GamaStudioEditor` | Apple, exists | everything above except the adapters, which it imports through `#if canImport` | panels, tools, hosts, file IO |
| `GamaStudioSamplePlugin` | stdlib, new | GamaPlugins | the in-repo plugin the gate loads |

The gate's `LIBRARIES` list grows to every stdlib row. A new stdlib target
that is not in the list fails a new gate check that diffs `Package.swift`'s
library targets against `LIBRARIES` minus a named Apple allow-list.

## 4. Rules that cut across phases

**Local-first adapters.** A subsystem whose real backend cannot run in the
gate is a protocol in a stdlib target plus one in-process implementation
tested there. The Apple adapter is a separate target that the editor loads
when available and that the ADR marks Provisional. The editor's UI for the
subsystem is tested against the in-process implementation, so the panels are
Implemented even where the backend is Provisional.

**Editor state versus document state.** Gizmo handles, timeline playhead,
asset thumbnails, AI proposals, sync presence, and diagnostics are editor
state: they live beside `bridge.root` or in `StudioModel`, are never written
to the document, and are never projected as document entities (the selection
highlight of ADR 0003 is the pattern).

**Tools are a subsystem.** Vision spec §15: gizmos are not viewport code.
`GamaStudioEditor` gains `Tools/` with a `ViewportTool` protocol
(`begin`, `update`, `end`, `cancel`, taking viewport-space input and the
picked entity, returning zero or more `DocumentCommand`s that `StudioModel`
runs inside one transaction per drag). Both viewports feed it.

**Every panel on every host.** A panel is a Gama view in `StudioApp` with a
regular and a compact placement (ADR 0008's 86-column rule, ADR 0020's wrap).
The macOS unit tests paint it; the simulator smoke drives it once per phase
with a `--smoke-<panel>` flag and reads its console notes, the ADR 0017/0018
pattern.

**Console verbs and notes.** Every feature a button performs also has a
console verb (ADR 0006), and every event a phase adds that a user would want
in the log is a coalescing note (ADR 0017).

**Deterministic core.** No `UUID`, `Date.now`, or random in stdlib targets;
identifiers are allocated by the document, time is a parameter, randomness
is seeded.

## 5. Phase 2b: editing core

Completes §62 except the asset browser (Phase 5).

**Gizmos (§15).** `GamaStudioEditor/Tools/`: `TransformTool` with modes
move, rotate, scale; handles X, Y, Z, XY, XZ, YZ (move), X, Y, Z, trackball
(rotate), X, Y, Z, uniform (scale); world/local space; snap increments
(translate 0.1, rotate 15 degrees, scale 0.1, each editable in the toolbar);
pivot at the selection's bounds center or the first entity's origin. Handle
entities are unpickable editor state under `bridge.root`, colored by axis,
scaled to a constant screen size each frame. A drag is one transaction: the
document changes only through `SetComponent(.transform)` per selected
entity; `Escape` or a cancel gesture restores the pre-drag transforms
through the transaction's rollback. macOS: mouse and trackpad. iOS and
visionOS: one-finger drag on a handle; the orbit gesture stays on empty
space. Toolbar: `Move`, `Rotate`, `Scale`, `World/Local`, `Snap` toggles;
keys `W`, `E`, `R`. Console: `tool move|rotate|scale`, `snap on|off`.

**macOS autosave (ADR 0011 gap).** `StudioAppDelegate` autosaves a document
that has a file, in place, 5 seconds after the last change, through
`StudioDocumentSession.save`; an Untitled document autosaves to a recovery
file under `~/Library/Application Support/GamaStudio Recovery/` keyed by a
per-window identifier persisted in `NSWindow` restoration state, restored
on relaunch through `UntitledRecovery` (ADR 0012's platform-neutral core).
Notes: `autosaved <name>` coalescing.

**Console follow-ups (ADR 0006).** `rotate <target> x y z` (degrees),
`find <predicate>` over names, kinds, and components (returns a selection),
history recall with Up and Down in the console field, and a focus shortcut
(`⌘L` on macOS; on touch a toolbar `Console` button focuses the field).

**Gate hardening.** Per-target test floors in `tools/check.sh`
(`MIN_TESTS_<Target>`), a tvOS build stage (`xcodebuild` for the library
against the tvOS simulator SDK, build only, since the editor has no tvOS
host), the `LIBRARIES` self-check of §3, and the `--smoke-tools` launch that
drives a gizmo drag on both simulators and requires the notes
`moved Box` and `rotated Box`.

**Exit:** ADR 0021. Gizmo tests in `GizmoTests` (handle picking in a real
`NSWindow`, one transaction per drag, cancel restores, snap arithmetic,
world versus local), autosave tests, console tests, gate stages green,
hand check on iPad and iPhone.

## 6. Phase 3: USD

**Document records.** `GamaAuthoring` gains `LayerStack` (ordered sublayer
paths with `muted` flags), `Reference` on an entity (a path plus an optional
prim path), `VariantSet` on an entity (name, ordered variants, selected
variant, each variant an ordered list of `Component` overrides), and
`Relationship` (name plus ordered target entity IDs). `ForeignPrim` holds an
opaque USDA block (type name, path, verbatim body) that Gama does not
interpret. Commands: `AddSublayer`, `RemoveSublayer`, `MoveSublayer`,
`SetLayerMuted`, `SetReference`, `ClearReference`, `AddVariantSet`,
`RemoveVariantSet`, `AddVariant`, `RemoveVariant`, `SelectVariant`,
`SetVariantOverride`, `SetRelationship`, `ClearRelationship`.

**Codec.** `GamaUSD` reads USDA it did not write: unknown prim types and
attributes become `ForeignPrim`s or foreign attributes on known prims and
round-trip verbatim; `def`, `over`, and `class` are kept; `subLayers`,
`references`, `variantSets`, `variantSet` blocks, and relationships map to
the records above. Composition is Gama's: `SceneDocument.composed()`
applies sublayers in order then the selected variants' overrides, and is
what the bridge projects. `.usdz` is a store-only zip whose first entry is
the root layer, written and read with a stdlib zip reader (no deflate);
external textures referenced by material texture paths are packed when
present. A `gama-studio --export out.usdz` must pass `usdchecker`.

**Editor.** A Layers panel (§8: new, duplicate, mute, solo, move, merge into
parent, reload, inspect), a Prim view in the inspector (§9: type,
composition source, transform ops, attributes, relationships, variants,
metadata, plus a raw USDA block for the entity), reference actions (open
source, break, reload, inspect), variant selection in the inspector.
Console: `layer add|remove|mute|solo|move`, `ref set|clear|reload`,
`variant select`, `export usdz`.

**Gate.** New goldens: `foreign.usda` (a hand-written file with prims Gama
does not know, read and written back byte for byte after `usdcat`
normalization), `layers.usda` with two sublayers, `variants.usda`,
`everything.usdz`. `--smoke-usd` opens the foreign fixture on both
simulators and requires `opened foreign.usda` and `kept 3 foreign prims`.

**Exit:** ADR 0022.

## 7. Phase 4: graph framework

**Nodes.** `GamaGraph` gains texture nodes (`TextureReference`, `Sample UV`
returning a color from a procedural pattern set: checker, gradient, noise,
voronoi, all deterministic), mesh nodes that emit `MeshData` (`GamaGeometry` starts in this phase with
`MeshData` and the primitive generators only; the kernel operations and the
procedural node families arrive in Phase 5), execution-flow nodes (`Sequence`, `Branch`, `ForEach` over
entities, `Event`) evaluated by a second evaluator pass that orders effects,
logic nodes (`Compare`, `And`, `Or`, `Not`, `Select`), rotation in Transform
Output, and typed non-float constants (`Int`, `Bool`, `String`, `Vector3`,
`Color`) editable in the panel.

**Evaluation.** `GraphEvaluator.evaluate` runs on a cooperative task off
the main actor; `StudioModel` awaits it and applies the resulting
`SetComponent`s in one transaction. Evaluation is pure over a `SceneDocument`
value, so the result is discarded if the document revision moved meanwhile
(then re-run).

**Canvas.** A spatial node canvas: nodes at `GraphNode.position` drawn as
boxes with ports, connections as lines, drag to move (`MoveGraphNode`), drag
port to port to connect, click to select, a palette to add. Built from Gama
views and one `NativeRegion`-free custom drawing (Gama's `DrawList` is
enough). Touch: same gestures with one finger.

**Exit:** ADR 0023, `GraphCanvasTests`, `ExecutionGraphTests`,
`--smoke-graph` on both simulators (add two nodes, connect, evaluate,
require `evaluated <graph>`).

## 8. Phase 5: assets

**Model.** `GamaAssets`: `AssetCatalog` (a set of `AssetRecord`s keyed by
`AssetID`, with kind from §27's list, relative path, size, metadata as
`[String: AssetValue]`, revision), `DependencyGraph` derived from the
document and catalog (entity to asset, asset to asset), `find dependents`,
`find dependencies`, `unused`, `relink(from:to:)` returning commands,
validation (missing files, unsupported kinds, texture size warnings).
`GamaAuthoring` gains `AssetReference` as a component (mesh from file,
texture on a material channel, audio file, animation clip file).
`GamaGeometry` grows from Phase 4's `MeshData` (positions, normals, UVs,
indices) and primitives into a half-edge `Mesh` with normals, bounds, extrude, inset, bevel (edge
chamfer), subdivide (Catmull-Clark), smooth (Laplacian), mirror, array,
join, separate, and the primitive generators; the geometry node family of
§20 maps onto them. `GamaReality` projects `MeshData` to `MeshResource`.

**Editor.** Asset browser panel (folder tree by kind, grid or list, search,
metadata pane, thumbnails rendered from a headless `ARView` on Apple
platforms and cached by revision), import (copy into the project's `Assets/`
folder next to the document; a document without a file keeps imports in the
recovery folder until saved), drag and drop to viewport, hierarchy, and
graph on macOS and iPad (UIKit drag interactions), relink dialog,
validation report. Console: `asset import|relink|find-unused`.

**Exit:** ADR 0024. MVG §62 complete. `--smoke-assets` imports a fixture
texture and mesh, requires `imported grid.png` and `imported cube.usda`.

## 9. Phase 6: animation

**Model.** `GamaAnimation`: `Timeline` (frame rate, range, markers, loop
region), `Keyframe<Value>` and `Curve` (linear, cubic Hermite with
tangents, step), `Track` bound to an entity's component path, `Clip` (named
set of tracks), `AnimationStateMachine` (states, transitions with conditions
over named parameters), `BlendTree` (1D and 2D blends), `Skeleton` (bones
with rest transforms and parents), `Skin` weights, IK solvers (two-bone
analytic, CCD with iteration cap), and a deterministic `Sampler` that
evaluates a clip or graph at a time into component values. `GamaAuthoring`
gains `AnimationBinding` (clip or state machine reference plus parameters)
and a `Skeleton` component. Sampling produces `SetComponent`s applied as
editor preview, not document edits, except when the user bakes.

**Editor.** Timeline panel (§26: tracks, keyframes, dope sheet, curve
editor, playhead scrub, play/pause/step, loop), skeleton editor (add,
extrude, reparent, mirror, orient, bind), parameter panel for state
machines. Playback drives the bridge through editor-state transforms, so
the document stays unchanged while playing. `GamaReality` projects skeletons
as bone markers.

**Exit:** ADR 0025. `--smoke-animation` scrubs to frame 24 and requires
`sampled Walk at 24`.

## 10. Phase 7: physics and compute

**Physics.** `GamaAuthoring` components `RigidBody` (mass, friction,
restitution, gravity scale, linear and angular damping, kinematic flag),
`Collider` (box, sphere, capsule, convex hull from a mesh, mesh),
`Joint` (fixed, hinge, ball, slider, distance, with limits), `ParticleEmitter`
(rate, lifetime, speed, spread, size, color over life). `GamaPhysics`
validates them and provides a deterministic semi-implicit Euler step with
sphere and box collision for tests and headless simulation; `GamaReality`
projects to RealityKit `PhysicsBodyComponent`, `CollisionComponent`,
`PhysicsJoint`, and `ParticleEmitterComponent`, on platforms that have them,
with the editor's simulate toggle running RealityKit physics as editor
preview and a bake action that writes final transforms as commands.

**Compute.** `GamaCompute`: a compute graph is a `GraphDocument` in the
`.compute` domain with the §25 node chain (`Input`, `Spawn`, `Initialize`,
`Force`, `Noise`, `Collision`, `Integrate`, `Output`) over a `ParticleBuffer`
(struct of arrays). The CPU evaluator is the reference. `GamaComputeMetal`
compiles the same graph to a Metal kernel source string, runs it, and a
macOS test asserts the two buffers agree within 1e-5 for 1,000 particles
and 60 steps. The touch hosts use the Metal evaluator when
`MTLCreateSystemDefaultDevice()` succeeds and the CPU one otherwise.

**Exit:** ADR 0026. Physics and Compute panels; console `physics simulate|bake`,
`compute run`.

## 11. Phase 8: AI

**Pipeline (§30, §54, §55).** `GamaAI`: `SceneIndex` (entities, components,
graphs, assets, cameras, lights, physics, flattened into searchable facts
with provenance tags `observed`, `derived`), `Intent` (a closed enum of
structured intents: create, set, duplicate, find, frame, procedural, with
typed slots), `IntentParser` protocol, `CommandPlanner` (intent plus index to
`[DocumentCommand]`), `Policy` (capabilities from §54; the planner refuses
commands outside the grant), `Proposal` (commands, the `SceneDiff` preview,
counts, the facts relied on, labeled observed versus inferred), `apply`
through `StudioModel` as one transaction. `SceneDiff` (§52) is a
`GamaAuthoring` value comparing two documents into per-entity, per-field
changes with a readable rendering.

**Backends.** `ModelBackend` turns text into an `Intent`. `RuleBackend`
(stdlib, tested) covers the §56 examples with a grammar over the console's
tokenizer plus synonyms and unit parsing. `GamaAIFoundation` wraps
Foundation Models with a `@Generable` `Intent` mirror, `#available`
26, falling back to `RuleBackend`; Provisional.

**Procedural (§32, §57).** A `ProceduralPlanner` maps a small set of
recipes (table, desk, staircase, shelf, room) to geometry graphs that stay
editable; the ADR lists the recipes so the claim is bounded.

**Search (§33).** Queries over the index: metallic, no material, unused
textures, main camera, has animation, referenced from another file, triangle
count above N.

**Editor.** AI panel: prompt field, proposal list with preview (the diff and
highlighted entities), Apply, Cancel, capability toggles, backend name.
Console: `ai <prompt>`, `ai apply`, `ai cancel`.

**Exit:** ADR 0027. `--smoke-ai` runs "create a 2 meter sphere" through the
rule backend and requires `proposed 1 change` then `applied 1 change`.

## 12. Phase 9: CloudKit

**Model (§35, §36, §53).** `GamaCloud`: `ChangeRecord` (document ID,
author, logical clock, base revision, the command's encoded inverse pair),
`ChangeJournal` (append-only, snapshot every N records), `Snapshot`,
`ConflictDetector` (two records with the same base revision touching the
same entity field), `Resolution` (ours, theirs, both as a variant), an
`OfflineQueue`, `Presence` (author, selection, last seen clock), `History`
(replay to any clock), and `Branch` (a named clock pointer over the
journal). `SyncTransport` protocol: `push`, `pull(since:)`, `presence`.
`MemoryTransport` is the tested implementation; the editor also backs it
with a folder so two windows on one Mac sync through files, which the tests
drive with two `StudioModel`s.

**Adapter.** `GamaCloudKit` maps records to `CKRecord`s in a private
database zone with subscriptions; Provisional, compiled in the gate, run by
hand only when a signing identity is present.

**Editor.** Sync status in the status line, presence list, history panel
with rollback, conflict prompt, branch menu. Console: `sync status|push|pull`,
`branch create|switch`.

**Exit:** ADR 0028.

## 13. Phase 10: plugins

**Model (§37).** `GamaPlugins`: `GamaPlugin` protocol (identifier, name,
version, required capabilities, `register(with:)`), `PluginRegistry`
(in-process, deterministic order), capability grants (deny by default;
`nodes`, `commands`, `importers`, `exporters`, `inspectors`, `tools`,
`validators`, `aiProviders`), registrations for each, and a `Manifest`.
This is cooperative in-process code, as in gama's Tier 1, and the docs
never call it isolation. `GamaStudioSamplePlugin` registers one of each
kind, and the gate loads it.

**Editor.** Plugins panel listing plugins, grants, and contributions;
contributed inspector sections and tools appear where the built-ins do.

**Exit:** ADR 0029, plus a closing ADR 0030 that records the state of every
vision-spec section as Implemented, Provisional, or Not built after Phase
10, replacing the "Not built" list in `AGENTS.md`.

## 14. Diagnostics and audio (folded into phases)

`GamaDiagnostics` lands in Phase 5 (asset validation is its first client)
and grows per phase: scene counts, warning rules from §41 and §51, frame
timings the hosts report. The Diagnostics panel lands in Phase 5.
`GamaAudio` lands in Phase 6 beside animation: an `AudioSource` component
(file reference, gain, loop, spatial) validated in stdlib and projected with
`AudioFileResource` on Apple platforms; the timeline shows audio clips.

## 15. Not in scope

Reality Composer `.reality` import (§38), glTF, the WebGPU, Vulkan, and
CUDA kernel backends (§21), out-of-process plugin isolation (Tiers 2 and 3),
real multi-user testing across devices, the App Store, and device signing.
These stay listed as Not built in the closing ADR.

## 16. Verification model

- Each task: a failing test first, then the code, then the target's suite,
  then the full gate before its commit.
- Each phase: whole-phase review by the most capable model over the phase's
  commit range, one fix wave, one scoped re-review, hand checks on the iPad
  Pro 11-inch (M5) and iPhone 17 simulators, a visionOS hand check when
  Device Hub can drive it, and the ADR.
- End: a final whole-branch review over everything since `5d80ee1`, one fix
  wave, and ADR 0030.
