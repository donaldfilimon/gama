# The `gama` MLIR dialect

Status: Locally proven by byte-exact fixtures and by passing emitted text
through `mlir-opt --allow-unregistered-dialect`. Hosted proof is head-specific
and belongs in the Roadmap ledger; do not infer it from this reference. This is
a textual emitter for pipeline consumption — not a Swift MLIR frontend.

`GamaLowering` has two entry points: `lower(module:)` for structural
(pre-layout) trees and `lower(laidOut:)` for frame-annotated trees — the
form GPU-compositor or ahead-of-time layout-baking pipelines want.
Everything is emitted in the *generic* op form, so no dialect registration
is needed. Try it: `GAMA_EMIT_MLIR=1 swiftly run swift run gama-demo
--emit-mlir | mlir-opt --allow-unregistered-dialect`.

## Op reference

| Op | Form | Attributes |
| --- | --- | --- |
| `gama.module` | region root | `sym_name` |
| `gama.empty` | leaf | none |
| `gama.text` | leaf | `text`, `fg`, `bg`, `sgr` (attribute bitmask) |
| `gama.stack` | region | `axis`, `spacing`, `halign`, `valign` |
| `gama.overlay` | region | `halign`, `valign` — the `ZStack` lowering |
| `gama.group` | region | none — the ViewBuilder/ForEach flatten sentinel, kept distinct from `overlay` |
| `gama.spacer` | leaf | `min` |
| `gama.divider` | leaf | `fg`, `bg`, raw `sgr` bitmask, optional `axis` (`"h"` or `"v"`) |
| `gama.padding` | region | `top`, `leading`, `bottom`, `trailing` |
| `gama.border` | region | `style`, `title`, `fg` |
| `gama.background` | region | `color` (`dense<[r,g,b]> : tensor<3xi8>` or `"default"`) |
| `gama.frame` | region | `width`/`height` or `min_width`/`max_width`/`min_height`/`max_height` (`-1` encodes unbounded), then `halign`, `valign` |
| `gama.styled` | region | `fg`, `bg`, `sgr` |
| `gama.interactive` | region | `id` (full 64-bit `i64`), `focusable` |

`.frame` and `.flexFrame` both emit `gama.frame`; their dimension attributes
distinguish the fixed and flexible forms. Attribute order is part of the
byte-level contract: dimensions, alignment, then the frame quad. Frame-annotated
lowering attaches `x`, `y`, `w`, and `h` (cells, `i64`) to every op and recurses
through laid children.

`LayoutEngine` rewrites a normal `.group` to a top-leading `.overlay`, so normal
laid lowering emits `gama.overlay`. A hand-built `LaidOutNode.group` still emits
`gama.group` with its frame quad. Similarly, a nil-axis divider inside a stack
gains `axis` from layout; structural lowering omits it, while laid lowering can
carry `"h"` or `"v"`. These are layout transformations, not alternate emitter
rules.

A plain divider emits `fg = "default"`, `bg = "default"`, and `sgr = 0 : i64`.
Colors render as `dense<[r, g, b]> : tensor<3xi8>` with `"default"` for the
terminal default. Strings escape quotes, backslashes, newlines, and tabs.
Attribute-free structural `gama.empty` and `gama.group` omit an empty `{}`
dictionary.

The emitter source (`Sources/GamaMLIR/Lowering.swift`) carries the same
vocabulary as a header comment; this file is the canonical reference.
