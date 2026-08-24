# Architecture and frame flow

Understand the retained tree, layout passes, drawing boundary, and event loop.

## Overview

An application produces a typed ``View`` hierarchy. A ``BuildContext`` assigns
stable ``NodeID`` values and renders that hierarchy into a backend-neutral
``RenderNode`` tree. ``LayoutEngine`` first measures and then places the tree,
producing ``LaidOutNode`` values clipped to the host's current bounds.

``FrameHost`` owns the mutable runtime state for one application instance:
actions, key handlers, focus, duplicate-identity diagnostics, dirty state, and
the latest dimensions. There are no process-global action or invalidation
registries. Multiple hosts therefore cannot invoke or dirty one another.

```text
App -> ViewBuilder/macros -> RenderNode -> LayoutEngine -> LaidOutNode
event -> FrameHost -> action or focus change -> dirty -> next frame
```

Backends either implement the poll-style ``Renderer`` protocol and use
``AppRuntime``, or retain a ``FrameHost`` and call `pump(size:)` from their
native scheduler. Platform hosts translate events and draw output; application
layout and focus semantics remain in GamaCore.
