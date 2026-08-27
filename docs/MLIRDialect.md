# The `gama` MLIR dialect

Status: Locally proven (deterministic emission; the parse gate runs the
output through `mlir-opt --allow-unregistered-dialect`, and the test suite
asserts op-level facts including the `gama.group` sentinel and full 64-bit
interactive ids) and hosted proven on the macOS job. This is a textual
emitter for pipeline consumption — not a Swift MLIR frontend.

`GamaLowering` has two entry points: `lower(module:)` for structural
(pre-layout) trees and `lower(laidOut:)` for frame-annotated trees — the
form GPU-compositor or ahead-of-time layout-baking pipelines want.
Everything is emitted in the *generic* op form, so no dialect registration
is needed. Try it: `GAMA_EMIT_MLIR=1 swiftly run swift run gama-demo
--emit-mlir | mlir-opt --allow-unregistered-dialect`.

## Op reference

| Op | Form | Attributes |
| --- | --- | --- |
| `gama.module` | region root | `name` |
| `gama.text` | leaf | `text`, `fg`, `bg`, `sgr` (attribute bitmask) |
| `gama.stack` | region | `axis`, `spacing`, `halign`, `valign` |
| `gama.overlay` | region | `halign`, `valign` — the `ZStack` lowering |
| `gama.group` | region | none — the ViewBuilder/ForEach flatten sentinel, kept distinct from `overlay` |
| `gama.spacer` | leaf | `min` |
| `gama.divider` | leaf | `fg`, `bg`, `sgr` |
| `gama.padding` | region | `top`, `leading`, `bottom`, `trailing` |
| `gama.border` | region | `style`, `title`, `fg` |
| `gama.background` | region | `color` (`dense<[r,g,b]> : tensor<3xi8>` or `"default"`) |
| `gama.frame` | region | `width`/`height` or `min_width`/`max_width`/`min_height`/`max_height` (`-1` encodes unbounded) |
| `gama.styled` | region | `fg`, `bg`, `sgr` |
| `gama.interactive` | region | `id` (full 64-bit `i64`), `focusable` |

Frame-annotated lowering additionally attaches `x`, `y`, `w`, `h` (cells,
`i64`) to every op. Colors render as `dense<[r, g, b]> : tensor<3xi8>` with
`"default"` for the terminal default; strings are escaped for quotes,
backslashes, newlines, and tabs.

The emitter source (`Sources/GamaMLIR/Lowering.swift`) carries the same
vocabulary as a header comment; this file is the canonical reference.
