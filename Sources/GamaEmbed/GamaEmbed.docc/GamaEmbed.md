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

Per the evidence ledger (`docs/Capabilities.md`), the C embedding surface
is locally proven by the Swift Testing ABI suites plus the compiled,
linked, and executed pure-C consumer gate (`scripts/check-c-abi.sh`), and
hosted proven on the Linux job. The static product folds the entry points
into the host binary; on Darwin and Android hosts the consumer also
carries the Swift runtime, a boundary `docs/backends/CEmbed.md` states
explicitly.

## Topics

### Swift-side entry

- ``GamaEmbed/GamaEmbed``
