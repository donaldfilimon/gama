# ``GamaEmbed``

Embed a Gama app in any C, JNI, game-engine, or FFI host through the
versioned `gama_embed_v1_*` ABI.

## Overview

GamaEmbed is the context-owned flat C ABI backend:
``GamaEmbed/GamaEmbed/makeContext(app:columns:rows:)`` wraps one app's
`FrameHost` behind an opaque pointer, and the `gama_embed_v1_*` symbol
family drives it from plain C.
Events go in through the key, pointer, and resize entry points; frames
come out as length-prefixed `DrawList` version 1 bytes. Ownership,
status codes, and the single-render-thread rule are normative in
`Sources/GamaEmbedABI/include/GamaEmbed.h`, and the canonical walkthrough
(including the pure-C consumer in `Examples/CEmbed`) is
`docs/backends/CEmbed.md`.

Resize dimensions clamp to a safe range, an oversized frame encoding
fails with an explicit status code rather than truncating, and a clean
context returns no frame at all: a NULL frame with length zero means
"nothing changed", never an error. Contexts are independent by
construction; two contexts share no state, which the independent-context
suite proves.

Capability status for the C embedding surface lives in
`docs/Capabilities.md` and is currently Unverified (catalog edits after
anchor `0f498d5`). This catalog does not restate hosted or local proof.
The static product folds the entry points
into the host binary; on Darwin and Android hosts the consumer also
carries the Swift runtime, a boundary `docs/backends/CEmbed.md` states
explicitly.

## Topics

### Swift-side entry

- ``GamaEmbed/GamaEmbed``
