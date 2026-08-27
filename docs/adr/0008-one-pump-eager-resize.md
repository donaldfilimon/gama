# 0008 — One frame pump, eager resize

Status: Accepted. Supersedes [0007](0007-frame-pumps.md).

Implements `../superpowers/specs/2026-08-27-frame-pump-unification-design.md`
(approved 2026-08-27). Delivery evidence is maintained in
`../Capabilities.md`.

## Context

ADR 0007 recorded four hand-rolled copies of `resize → clearBack → paint →
emit` and named the cost: a `.resize` was visible to handling code
immediately on Embed and WASM, but only at the next pump on TUI and
AppleUI. Two backends therefore disagreed with the other two about what
`size` meant during event handling, and the four copies drifted
independently — WASM's focus-reconciliation follow-up frame existed
nowhere else.

## Decision

**One canonical pump owns resize policy, the dirty gate, and pump
ordering. The policy is eager.**

`.resize` updates the pump's size and invalidates the host *before* the
event is forwarded, on every backend. Handling code now observes one
consistent extent regardless of which host it runs under.

The type is split across the GamaCore/GamaDraw dependency edge, because
`CellBuffer` lives in GamaDraw and GamaDraw depends on GamaCore:

- `GamaCore/HostPump.swift` — the policy. Consumes a `FrameHost`, owns
  `size`, and returns `AdvancedFrame?` (laid-out node + `followUp`).
  Stdlib-only and `~Copyable`, matching the host and runtime it joins. It
  stays in GamaCore deliberately: `check-embedded.sh` compiles GamaCore
  alone, so a pump in GamaDraw would sit outside the Embedded proof.
- `GamaDraw/HostPump+CellBuffer.swift` — `advance(into:emit:)`, doing
  resize-if-needed → `clearBack` → `paint` → `emit`.

Emission stays per-backend: ANSI diff, HTML, `DrawList` bytes,
CoreGraphics. No backend forks layout, paint order, or the dirty gate.

`AdvanceOutcome.followUp` generalizes WASM's special case — the host can
be left dirty by focus reconciliation, and every backend now schedules the
extra frame the same way.

Buffer resizing is folded in as `CellBuffer.resizeIfNeeded(_:)`, which
normalizes before comparing. A plain `size != newSize` check is wrong:
`size` holds the already-normalized extent, so any request above
`maximumCellCount` never compares equal and would re-allocate — and force
a full present — on every frame.

## Consequences

- TUI and AppleUI change observable resize timing. This is a deliberate,
  pre-release source-visible behavior change; `../SceneMigration.md`
  carries the note.
- Embed and WASM are behavioral no-ops. Their tests passing **unchanged**
  is the evidence that the canonical shape matches what they already did.
- The pump semantics are pinned once, in `HostPumpTests`, instead of four
  times across backend suites.
- Out of scope, unchanged: frame pacing/vsync, damage regions, partial
  repaints.
