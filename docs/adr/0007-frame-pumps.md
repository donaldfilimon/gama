# 0007 — Four frame pumps

Status: Provisional — unification is a Slice C sign-off item; this record
documents current reality, not a lock.

## Context

Each backend hand-rolls the `resize → clearBack → paint → emit` sequence:
`AppRuntime`+`TUIRenderer` (lazy resize, dirty-gate in the runtime),
`GamaWASM` (eager resize on the event, gate in `frame()`), `GamaEmbed`
(eager, gate in `frame()`), and `GamaHostView` (lazy, gate in the driver).
Consequently a `.resize` takes effect for the *handling* code immediately
on Embed/WASM but only at the next pump on TUI/AppleUI.

## Decision (interim)

The divergence is tolerated and documented rather than papered over. The
approved [scene-first app-shell design](../superpowers/specs/2026-08-27-scene-first-app-shell-design.md)
keeps all surfaces on the shared `FrameHost`, but deliberately does not add
frame-pump or resize-policy unification to that milestone. Extracting one
canonical `advance` step still alters observable semantics and remains a
separate Slice C decision.

## Consequences

Backend authors must read the per-backend guides for exact resize timing;
any new backend should copy the Embed pump (eager resize, gate inside
`frame()`) as the least surprising shape until unification lands, at which
point this record is superseded.
