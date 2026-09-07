# ``GamaMLIR``

Emit Gama view trees as the textual `gama` MLIR dialect for pipeline
consumption.

## Overview

GamaMLIR is a deterministic textual emitter, not a Swift MLIR frontend.
``GamaLowering`` has two entry points: ``GamaLowering/lower(module:name:)``
for structural (pre-layout) `RenderNode` trees, and
``GamaLowering/lower(laidOut:name:)`` for frame-annotated `LaidOutNode`
trees, the form GPU-compositor or ahead-of-time layout-baking pipelines
want, where every op additionally carries `x`, `y`, `w`, `h` cell
attributes.

Everything is emitted in the *generic* op form, so consumers need no
dialect registration: the output parses with
`mlir-opt --allow-unregistered-dialect` as-is. The dialect keeps GamaCore's
semantic distinctions intact: `gama.overlay` is the `ZStack` lowering
while `gama.group` is the ViewBuilder/ForEach flatten sentinel, and
`gama.interactive` carries full 64-bit ids. Colors render as
`dense<[r, g, b]> : tensor<3xi8>` with `"default"` for the terminal
default, and strings are escaped deterministically.

Capability status for the emitter lives in `docs/Capabilities.md` and is
currently Unverified (catalog edits after anchor `0f498d5`). This catalog
does not restate hosted or local proof. The canonical
op-by-op reference with attributes is `docs/MLIRDialect.md`; try the
emitter with `swiftly run swift run gama-demo --emit-mlir`.

## Topics

### Lowering

- ``GamaLowering``
