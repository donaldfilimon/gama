# C embedding and DrawList wire format

Integrate Gama with Android, C, C++, game engines, and other foreign hosts.

## Context lifecycle

`GamaEmbed.makeContext(app:)` returns a caller-owned opaque context. Destroy it
exactly once with `gama_embed_v1_context_destroy`. Every context owns its host,
focus, actions, dirty flag, dimensions, and frame bytes. Calls for one context
are single-render-thread only; contexts do not share mutable framework state.

The complete declarations, null behavior, return codes, and pointer lifetime
are committed in `Sources/GamaEmbedABI/include/GamaEmbed.h`. The frame pointer
is valid until the next frame request or context destruction. The Android
sample under `Examples/Android` packages the Swift runtime, links a JNI shim,
decodes the same bytes in Kotlin, and renders them through `Canvas`.

## Binary format version 1

All integers are little-endian. The 20-byte header is:

| Field | Type | Meaning |
| --- | --- | --- |
| magic | `u32` | bytes `GAMA` |
| version | `u32` | `1` |
| width, height | `i32`, `i32` | nonnegative grid dimensions |
| count | `u32` | number of commands |

Command `0` is a fill rectangle: `i32 x,y,w,h`, followed by RGB bytes and one
default-color flag byte. Command `1` is text: `i32 x,y`, foreground and
background colors, `u16` attribute bits, then a `u32` byte length and UTF-8.

Decoders must reject bad magic/version, negative dimensions, impossible
counts, truncated commands, negative fill sizes, invalid lengths, unknown
kinds, and trailing bytes. Encoders clamp public integer geometry to the
stable signed 32-bit wire range.
