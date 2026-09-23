# ADR 0007: A typed graph framework on the same command bus

Status: Accepted (2026-09-23)

## Context

The spec's §18 asks for one generic, typed graph system, not a set of
unrelated editors. Its pieces are:

- `PortType`, from `float` through `execution` plus `custom`;
- `GraphDocument` with nodes, ports, connections, and metadata;
- domains: Geometry, Material, Animation, Physics, Particle, Compute,
  Logic, Scene, Audio, and AI.

§61 Phase 4 lists `GraphDocument`, `GraphNode`, `GraphPort`,
`GraphConnection`, an evaluator, and a graph editor, then specializations.
The spec's principle 5 says graphs use the same command infrastructure as
everything else, and its command list names `ConnectGraphCommand` and
`DisconnectGraphCommand`.

Donald asked for "a typed graph framework" on 2026-09-23. Two choices were
put to him:

- **Scope:** he chose everything, including the editor.
- **First specializations:** he chose both material and transform.

## Decision

1. **Graphs are document state in `GamaAuthoring`.** `SceneDocument` holds
   `GraphDocument`s in authored order.
   - Each `GraphNode` stores its own port signature (`[GraphPort]`) and a
     definition name. The document can therefore check connection types,
     single-input fan-in, and cycles without knowing what a node computes.
   - Types must match exactly. Conversions are explicit nodes, so a graph
     never changes meaning through an implicit cast.
   - Constants are `GraphValue`s. Inputs and outputs are separate
     namespaces.
   - Entity references may dangle: deleting an entity never edits graphs,
     and such a reference evaluates as unset.
2. **Every graph edit is an invertible `DocumentCommand`:** `CreateGraph`,
   `DeleteGraph`, `RenameGraph`, `AddGraphNode`, `RemoveGraphNode`,
   `MoveGraphNode`, `SetGraphValue`, `ConnectPorts` (which replaces an
   input's feed), and `DisconnectPorts`.
   - Each is in `CommandRoundTripTests`.
   - Connections are kept in one canonical order, so undo restores an
     equal document.
   - They report `.graphChanged`, which the RealityKit bridge ignores.
3. **Evaluation lives in a new `GamaGraph` target, standard library only.**
   `NodeDefinition` is pure: its `compute` maps inputs to outputs.
   `NodeRegistry.standard` holds:
   - constants: float, vector3, color;
   - float math: add, subtract, multiply, divide, clamp, mix;
   - vector3: compose, split, add, scale;
   - color: compose, mix, multiply;
   - two outputs (below).

   `GraphEvaluator` runs nodes in topological order, ties broken by
   authored order, so results are deterministic. An unconnected input
   without its own value uses its definition's default. For scene edits it
   evaluates only output nodes and what feeds them, so a broken scratch
   node (a division by zero, an unknown type) does not block edits to the
   rest of its graph. It is a `Sendable` value,
   not the spec's `actor`: it has no state to protect, and a caller can
   still run it off the main actor.
4. **Graphs reach the scene only as ordinary commands.** An output node's
   `emit` returns `SetComponent`s:
   - **Material Output** writes `Material`. Its channels saturate to 0…1,
     as a PBR output does.
   - **Transform Output** writes position and scale and keeps rotation.

   `EvaluateGraph` is a `DocumentCommand` that evaluates against the
   document it is applied to and applies those edits through
   `CompositeCommand`. Its inverse is the recorded inverse of each edit,
   so redo replays rather than re-evaluates. Editors run a graph edit and
   `EvaluateGraph` in one transaction, so the edit and its effect on the
   scene undo together. An evaluation failure, such as a division by zero,
   refuses the edit if it happens in a node that feeds an output, and
   nothing changes. An output with no target, or a
   deleted one, does nothing.
5. **Persistence (extends ADR 0005).** Graphs save under a root
   `Scope "GamaGraphs"`:
   - one `NodeGraph` per graph;
   - one typeless prim per node, named `n<id>`, holding `name:type`
     signature arrays;
   - typed `gama:value:<input>` constants;
   - `gama:link:<input> = "n2.<output>"` connections.

   A document that has ever held a graph writes format version 2, keeping
   `gama:nextGraphID` so graph identifiers are never reused. A document
   that never did is unchanged byte for byte and stays version 1. The name
   `GamaGraphs` is reserved at every depth, like `Looks`. The reader
   refuses the following rather than drop them:
   - node prims that are typed or have children;
   - values or links for undeclared inputs;
   - allocators out of range.

   `usdchecker` accepts the new golden, and its `usdcat` reformatting reads
   back to the same document.
6. **Two editing surfaces, one path.**
   - **Console (ADR 0006):** the `graph` verbs `new`, `list`, `show`,
     `nodes`, `add`, `remove`, `connect`, `disconnect`, `set`, `rename`,
     `delete`, and `apply`.
   - **Graph editor panel:** it replaces the inspector while the toolbar's
     "Graph" toggle is on. It offers graph switching, new material and
     scene graphs, the node list, an Add picker filtered by the graph's
     domain, and the selected node's inputs:
     - connected inputs, each with a disconnect button;
     - constants, with −/+ for floats;
     - Sel, which points an entity input at the selection;
     - output Link and input Here buttons, for connecting.

   Both surfaces call `StudioModel`'s graph methods (`editGraph` and
   friends), which bundle each edit with `EvaluateGraph`. The active graph,
   selected node, pending link, and picker position are editor state,
   never in the document. The selected node and pending link are stored
   with their graph and ignored once another graph is shown. Node ids
   restart at `n1` in every graph, so an undo or a console `graph delete`
   that switches graphs must not retarget them.

## Consequences

- A new domain (geometry, physics, and so on) is new `NodeDefinition`s,
  possibly a new output node. The model, commands, persistence, console,
  and editor are unchanged.
- Measured 2026-09-23:
  - removing evaluation's effect fails three `GamaGraphTests`;
  - dropping links in the reader fails the round-trip and fixture tests;
  - the panel test builds a material graph using buttons only and undoes
    a link together with its effect.
- An output re-applies only when its graph is edited or applied. A hand
  edit to a targeted entity stays until the graph is next edited or
  "Apply" is pressed. That is deliberate: no hidden re-evaluation on
  unrelated edits.
- Not built:
  - textures, meshes, and execution flow. The port types exist, but no
    node produces them.
  - rotation in the transform output, which needs trigonometry for the
    stdlib-only target;
  - typing non-float constants in the panel (the console does it);
  - a spatial node canvas. The panel is a list, and node positions are
    stored for a future canvas.
  - evaluation off the main actor;
  - plugin node registration from outside the process.
