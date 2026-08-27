# C embedding backend (GamaEmbed)

Status: Locally proven (independent-context and ABI-addition suites, plus
the pure-C consumer gate) and hosted proven on the Linux job
(`check-c-abi.sh`). The static library folds the versioned entry points
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

Interrogate the ABI revision at runtime with
`gama_embed_v1_abi_version()` (always `1` for this family). Create/resize
dimensions clamp to `1...INT32_MAX`, and the cell grid enforces its own
maximum cell count. A clean (not dirty) frame returns NULL and writes
length zero — distinct from the `-3` failure.

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
