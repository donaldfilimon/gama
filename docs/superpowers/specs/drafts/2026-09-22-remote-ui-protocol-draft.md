# Remote UI protocol — draft

Status: Draft. Open questions, not a commitment. Nothing here is built.

## Why this is written down

A survey of the tree found no design, ADR, or code for remote UI anywhere.
It also found that two of the three hard parts already exist in shipped
form for other reasons, and that recording which is which saves the next
attempt from re-deriving it.

## What already exists and is reusable

**A frame format.** `DrawList` (ADR 0005, `Sources/GamaDraw/DrawList.swift`)
is a little-endian byte stream with a `GAMA` magic, a `u32` version, grid
dimensions, and typed fill/text commands. Its decoder is written for
hostile input: the command count is bounded against the remaining payload
*before* any allocation, UTF-8 is validated by hand against RFC 3629, and
every failure is a typed `DecodeError` rather than a trap. Its versioning
rule — bump the integer, keep version 1 decodable — is already the rule a
wire protocol needs. It was built so "C, JNI, and game engines" could
decode a frame in about forty lines, which is the same bar a remote
renderer has to clear.

**A negotiation pattern.** The WASM backend publishes two export tiers
(`docs/backends/WASM.md`): `gama_web_v1_*` and the argument-compatible,
status-reporting `gama_web_v2_*`. Its discipline is worth copying exactly:
a published signature is frozen forever, a new result contract means a new
symbol family, and the failure sentinels are ordered so that the
installed-host check precedes argument validation (`-1` no host, `-2`
invalid input — a bad input with no host still reports `-1`).

**A foreign-host precedent.** `GamaEmbed`/`GamaEmbedABI` already lets code
outside Swift drive a Gama app: opaque context pointer, versioned
`gama_embed_v1_*` entry points, single render thread, events in and
`DrawList` bytes out. A remote protocol is that contract with a socket
where the function call was.

## What does not exist and has to be designed

- **An event channel in the payload.** `DrawList` is one-directional and
  carries no input. Today events cross a boundary only as WASM *export
  function signatures*, never as bytes. A remote protocol needs its own
  encoding for `InputEvent`, including the cases added recently
  (`.gamepad`) and whatever follows.
- **A session and handshake.** Nothing in the tree negotiates anything
  inside a payload. Version and capability exchange has to be invented,
  and `docs/Capabilities.md`'s vocabulary is the honest source for what a
  peer may claim.
- **Delta encoding.** `DrawList` is always a full frame. The TUI backend
  already diffs cells into minimal ANSI writes; a remote renderer wants the
  same idea at the wire level, and the existing `CellBuffer` diff is the
  obvious place to look before inventing one.
- **Transport and security.** Untouched. The manifesto's own §58 and §187
  are the constraint: a remote peer must not inherit host capabilities, and
  nothing executable may be deserialized. This is where the work is
  genuinely hard, and it should be designed before any transport is chosen,
  not after.

## Open questions

1. Is the first target a *debugging* channel (one trusted local peer over
   a unix socket, which makes the security story small) or a *product*
   channel (untrusted network peers, which makes it the whole story)?
   These lead to different protocols and the answer changes everything
   below it.
2. Does the remote renderer receive `DrawList` frames, or the semantic tree
   above them? Frames are simpler and already specified; the semantic tree
   preserves accessibility and per-platform expression, which is the
   manifesto's actual objective. Sending frames may foreclose that.
3. Should this share the plugin Tier 3 message ABI rather than inventing a
   second one? Both are "capability-negotiated transport across a process
   boundary." Tier 3 is itself unbuilt and undecided, so the honest
   sequencing question is which one gets designed first.

## Relationship to plugin Tier 3

`docs/Plugins.md` describes Tier 3 as an out-of-process plugin over a
versioned message ABI, and the superseded plugin draft sketches it as "the
`GamaEmbed` contract with the roles inverted." That is the only other place
in the repository where a capability-negotiated non-in-process transport
has been thought about at all. Whichever is designed first should expect to
carry the other.
