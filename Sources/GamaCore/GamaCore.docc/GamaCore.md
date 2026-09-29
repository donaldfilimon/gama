# ``GamaCore``

Build declarative interfaces once and host them on multiple rendering edges.

## Overview

GamaCore turns generic Swift views into a retained ``RenderNode`` tree, lays
that tree out into ``LaidOutNode`` values, and routes typed ``InputEvent``
values through a host-owned ``FrameHost``. It has no Foundation or platform
dependency and is shared unchanged by terminal, Apple, WebAssembly, C/Android,
Embedded, and MLIR integrations.

Application state uses ``Signal``, ``State``, and ``Binding``. State mutations
caused by Gama actions are rendered by the owning host. External asynchronous
state sources explicitly request a frame from their backend, avoiding hidden
process-global invalidation.

## Topics

### Essentials

- <doc:Architecture>
- <doc:CompositionAndState>
- <doc:BackendAuthoring>
- <doc:EmbeddingAndDrawList>
- <doc:PlatformsAndLimitations>
- <doc:Testing>
- <doc:Migration>

### Composition

- ``View``
- ``ViewBuilder``
- ``RenderNode``
- ``Text``
- ``Button``
- ``VStack``
- ``HStack``
- ``ZStack``
- ``TextField``
- ``Toggle``
- ``ProgressView``
- ``ForEach``

### Runtime

- ``App``
- ``FrameHost``
- ``AppRuntime``
- ``Renderer``
- ``InputEvent``
- ``PointerEvent``
- ``PointerGesture``
- ``InteractionIdiom``
- ``PointerPolicy``
- ``InteractiveRegion``
- ``NodeID``
- ``BuildContext``
- ``Signal``
- ``State``
- ``Binding``
- ``SubscriptionContext``
- ``CompletionStatus``
- ``FailureExitCode``

### Layout and style

- ``LayoutEngine``
- ``LaidOutNode``
- ``TextLayout``
- ``Rect``
- ``Size``
- ``TextStyle``
- ``BorderGlyphs``
- ``Color``
- ``LayoutMetrics``

### Native presentation

A GUI host that presents Gama views as platform controls (ADR 0017) lays
out with its own ``LayoutMetrics``, reads the ``ControlDescriptor`` side
table `FrameHost` keeps, reduces each frame to a ``PresentedNode`` tree, and
applies the ``PresentationOp`` list ``PresentationDiff`` computes between
frames. Other backends never read the descriptor table or build the
tree. The registrations still shape the shared frame: `ProgressView` now
compiles to a non-focusable `interactive` node, so it appears among the
interactive regions and in the MLIR dialect, while pointer hit-testing looks
through it.

- ``ControlDescriptor``
- ``PresentedNode``
- ``PresentedKind``
- ``PresentationID``
- ``PresentationDiff``
- ``PresentationOp``
