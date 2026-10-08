# GPU compositor — draft

Status: Draft. Open questions, not a commitment. Nothing here is built.

## Starting position: genuinely zero

A repository-wide search — not filtered to Swift, including `Package.swift`,
`WebHost/gama.js`, and CI configuration — finds no reference to Metal,
Vulkan, Direct3D, WebGPU, WebGL, `CALayer`, `MTKView`, or a `<canvas>`
rendering context anywhere. Every backend is CPU-side today:

- `GamaAppleUI` draws in `NSView.draw(_:)` via CoreGraphics and
  `CTLineCreateWithAttributedString`.
- `GamaWASM` emits an HTML string of `<pre>`/`<span>` runs for direct DOM
  assignment.
- `GamaTUI` writes ANSI to a terminal.

`docs/Capabilities.md` has no GPU row at all — it is not tracked as
Blocked or Provisional, it is simply absent. The one `Canvas` hit in the
tree is `android.graphics.Canvas` in the Android sample, a foreign host
consuming decoded `DrawList` bytes, not a Gama-authored GPU path.

## The question this has to answer first

Gama's render output is a grid of styled cells. A GPU is not obviously the
right instrument for that, and the honest first question is not "which
API" but **what a GPU is for here**.

Plausible answers, which lead to very different projects:

- **Text throughput.** Glyph atlas plus instanced quads, to make very
  large grids cheap. This is the one that fits the existing architecture
  most directly: `DrawList` is already a flat command list, and a cell grid
  is the friendliest possible thing to instance.
- **Effects the cell model does not have.** Smooth scrolling, blur,
  per-pixel transitions. This implies a richer render graph than a cell
  grid, which is a change to the IR, not a backend swap.
- **Embedding Gama into a GPU application** — a game engine drawing Gama UI
  into its own frame. That is arguably not a compositor at all but an
  extension of the existing `GamaEmbed` C ABI, and might need no new
  rendering code in Gama whatsoever.

The third possibility is worth ruling in or out early, because if it is
the real requirement then most of this document is unnecessary.

## Constraints that already bind

`GamaCore`, `GamaPlugin`, `GamaDraw`, `GamaEmbed`, and `GamaMLIR` may not
import platform modules; `scripts/portable-global-state.py` enforces it
over one `TARGETS` list. A GPU backend therefore lives outside all of them,
alongside `GamaAppleUI` — the same place `GamaPlatformServices` sits
relative to host services. ADR 0001 ("own the rendering") already settled
that Gama does not wrap platform widgets, so a GPU path would be another
renderer of the same IR, not a different application model.

Shipped products carry no runtime package dependencies (ADR 0012, enforced
by `check-package-graph.sh`), so a GPU backend may not pull in a shader
compiler or math library as a package dependency without that decision
being made explicitly.

## Open questions

1. What is the GPU *for* (above)? Without an answer this cannot be scoped.
2. Metal first? It is the only one with an existing sibling backend to
   borrow lifecycle from, and the only one testable on this machine. But
   `check-apple.sh` runs headless in CI, and a GPU test that requires a
   device is a new category of evidence that `docs/Verification.md`'s
   ladder does not currently have a rung for.
3. How is correctness proven? The existing backends are provable because
   their output is deterministic bytes — a cell buffer, a `DrawList`, an
   HTML string. A GPU frame is pixels, and `docs/Verification.md` is
   explicit that bitmap comparison must not become the only mechanism.
   Deciding what a GPU backend's golden artifact *is* may be the hardest
   part of this project, and is worth settling before any code.
