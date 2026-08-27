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
- ``Renderer``
- ``InputEvent``
- ``Signal``
- ``Binding``

### Layout and style

- ``LayoutEngine``
- ``TextLayout``
- ``Rect``
- ``Size``
- ``TextStyle``
- ``Color``
