# C embedding backend (GamaEmbed)

Status: Unverified. Capability status lives in
[`Capabilities.md`](../Capabilities.md); this guide does not restate
hosted or local proof. The static library folds the versioned entry points
into the host binary.

## Contract

The header is `Sources/GamaEmbedABI/include/GamaEmbed.h`. `GamaEmbedContext`
is an opaque struct pointer (compile-time type safety; never a `void *`).
Every function is single-render-thread only. The frame pointer stays valid
until the next frame call or context destruction.

Status codes (also an `enum` in the header):

| Code | Name | Meaning |
| --- | --- | --- |
| `0` | `GAMA_EMBED_OK` | Success |
| `-1` | `GAMA_EMBED_ERR_NULL_CONTEXT` | The context pointer was NULL |
| `-2` | `GAMA_EMBED_ERR_INVALID_KEY` | Key code did not translate |
| `-3` | `GAMA_EMBED_ERR_FRAME_TOO_LARGE` | Frame encoding exceeded INT32_MAX bytes (written to `*output_length`; the call returns NULL) |
| `-4` | `GAMA_EMBED_ERR_INVALID_POINTER` | A pointer phase, kind, button or modifier code was outside the `GAMA_EMBED_POINTER_*` tables |

Interrogate the ABI revision at runtime with
`gama_embed_v1_abi_version()` (always `1` for this family). Create/resize
dimensions clamp to `1...INT32_MAX`, and the cell grid enforces its own
maximum cell count. A clean (not dirty) frame returns NULL and writes
length zero — distinct from the `-3` failure.

**Scaling means resizing in cells.** The ABI has no font, point or pixel
unit, and it will not gain one: the embedder owns pixels. To make text
bigger or smaller, the host picks a new font size, measures its cell, works
out how many whole cells fit its view, and calls the resize entry point with
that grid, exactly as it does when the view itself changes size. The Android
example is designed to do this with a 14 sp font, so that it follows density
and the system font scale; only its build is checked, not that runtime
behavior.

## Walkthrough

`Examples/CEmbed/main.c` is the complete lifecycle the CI gate compiles
(`-std=c17 -Wall -Wextra -Werror`), links, and runs:

1. `gama_embed_v1_abi_version()` → must be 1.
2. `gama_embed_v1_context_create(40, 12)` → non-NULL context running the
   built-in diagnostic app (Swift hosts use `GamaEmbed.makeContext(app:)`).
3. `gama_embed_v1_needs_frame` / `gama_embed_v1_frame` → frame bytes whose
   first four bytes are the `GAMA` magic; decode with any 40-line reader of
   the DrawList wire format (`GamaCore.docc/EmbeddingAndDrawList.md`).
4. `gama_embed_v1_key(ctx, 7, 0, 0, 0)` (tab) then code 5 (enter) → drive
   focus and actions; hostile inputs return the documented codes.
5. `gama_embed_v1_context_destroy(ctx)` — the pointer must not be reused.

Frame storage is context-owned raw memory, reused frame-over-frame and
grown to the high-water size; it is freed with the context.

## Pointer samples (ADR 0018)

`gama_embed_v1_pointer(ctx, column, row, pressed)` stays the primary
press/release shorthand. Hosts with richer input call the additive
`gama_embed_v1_pointer_event(ctx, phase, kind, button, modifiers, column,
row, scroll_columns, scroll_rows, pointer_id, timestamp_millis)` with the
`GAMA_EMBED_POINTER_*` codes: phases down, move, up, cancel, hover, scroll
and stationary; kinds mouse, touch and pen; buttons primary, secondary and
middle (0 to 31 accepted); modifier bits shift, control, option and command.
Scroll deltas are in cells, positive rows revealing the lines below. A
negative timestamp (`GAMA_EMBED_POINTER_NO_TIME`) means the host has no
clock. The NULL-context check comes first; an out-of-table code returns
`GAMA_EMBED_ERR_INVALID_POINTER`. The host only translates: Gama recognizes
tap, drag, long press, hover and scroll with the idiom passed to
`GamaEmbed.makeContext(app:columns:rows:idiom:)` (desktop by default and for
`gama_embed_v1_context_create`).

For long press, re-query `gama_embed_v1_pointer_deadline(ctx, &millis)`
after each pointer call. It writes the pending deadline on the host's own
clock, or `GAMA_EMBED_POINTER_NO_TIME` when no press waits on one (and
saturates rather than wrapping past `INT64_MAX`); at that time the host
delivers a stationary sample for the pressed pointer. `abi_version` stays 1:
both entry points are additions to the v1 family. The rule, shared with the
WASM tiers ([WASM.md](WASM.md)): a symbol family names a closed contract, and a new entry point joins an
existing family only when that family's stated contract admits it; otherwise
it opens the next family number. The C `v1` contract is "status-returning
calls on a context, with the open `GAMA_EMBED_ERR_*` enum", which admits
additive calls. The WASM `v2` contract is "exactly the `v1` exports, with
status results", which is closed, so exports with no `v1` counterpart open
`v3`. The same rule applied to the same additions gives C `v1` and WASM `v3`. The pointer constants carry
their category in the name (`GAMA_EMBED_POINTER_PHASE_*`, `_KIND_*`,
`_BUTTON_*`, `_MOD_*`), one enum per category. `main.c` exercises the
invalid-code, hover, scroll, touch press and release paths and both deadline
answers; `EmbedPointerABITests` drives a drag, a stationary long press and
the idiom through a context whose app registers a pointer handler.
