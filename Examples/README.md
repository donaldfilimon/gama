# Gama examples

The task-oriented command map, proof boundary, and platform-specific caveats
live in [`docs/Examples.md`](../docs/Examples.md). This file remains the short
source-tree index.

The examples exercise the same `GamaCore` semantics through each host:

- `gama-demo` (root package): counter, form input, toggle, progress, list,
  disabled controls, terminal events, and `--emit-mlir` structural/laid-out MLIR.
- `AppleHost/main.swift`: minimal AppKit host; `GamaAppleUI` also compiles its
  UIKit branch for iOS, tvOS, and visionOS in the acceptance matrix.
- `WebHost/` at the repository root: dependency-free browser/WASM reactor host.
- `CEmbed/main.c`: versioned C ABI lifecycle and draw-list consumer.
- `Android/`: Kotlin/JNI app that decodes the shared draw list and proves an
  input-driven state/frame change in an emulator.
- `Embedded/main.swift`: portable app used as an Embedded Swift composition
  example; the gate whole-module compiles and relocatably links `GamaCore`.

Run every locally provisioned proof with `./scripts/check.sh`. Missing runtime
or SDK prerequisites fail closed.
