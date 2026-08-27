# Gama umbrella — frame-pump unification and resize policy (Slice C, wave 2)

Date: 2026-08-27. Status: **approved** (Donald approved unification and a
single resize policy on 2026-08-27; this document records the design).
Delivery evidence is maintained in `docs/Capabilities.md`.

Supersedes the interim decision of `docs/adr/0007-frame-pumps.md` once
implemented; ADR 0007 is then updated from Provisional to Superseded with a
pointer here, and a new ADR records the final shape.

## Problem (from ADR 0007)

Each backend hand-rolls `resize → clearBack → paint → emit`:

| Backend | Resize | Dirty gate | Emit |
| --- | --- | --- | --- |
| `AppRuntime` + `TUIRenderer` | lazy (next pump uses `renderer.size`) | in the runtime loop | ANSI diff from `CellBuffer` |
| `GamaWASM` | eager (event updates `size`) | inside `frame()` | HTML via `HTMLSerializer` |
| `GamaEmbed` | eager | inside `frame()` | `DrawList.encode()` bytes |
| `GamaHostView` (AppleUI) | lazy | in the driver | CoreGraphics from the paint |

A `.resize` is visible to handling code immediately on Embed/WASM but only
at the next pump on TUI/AppleUI. Four copies of the same sequence drift
independently (WASM's focus-reconciliation follow-up frame exists nowhere
else).

## Decision

### D1. Single resize policy: eager

ADR 0007 already names the Embed pump "the least surprising shape". Adopted:
a `.resize` event updates the pump's size and dirties the host *before* any
other handling occurs, on every backend. TUI and AppleUI change observable
behavior; the tests that pin lazy timing are updated to pin eager timing,
and `docs/SceneMigration.md` gains a migration note.

### D2. One canonical pump type in GamaCore

```swift
// Proposed — GamaCore, stdlib-only, Embedded-safe, ~Copyable like the
// host and runtime it joins.
public struct HostPump: ~Copyable {
    public init(host: consuming FrameHost, size: Size)
    /// Eager resize policy lives HERE: `.resize` updates `size`,
    /// invalidates, then forwards; every other event forwards untouched.
    public mutating func handle(_ event: InputEvent)
    /// The canonical step. Returns nil when the host is clean. Otherwise:
    /// pump(size:) → clearBack → CellPainter.paint, then borrows the
    /// painted buffer to `emit`. `followUp` is true when the host is
    /// still dirty afterwards (focus reconciliation) — the WASM
    /// requestFrame rule, standardized.
    public mutating func advance<E>(
        emit: (borrowing CellBuffer) throws(E) -> Void
    ) throws(E) -> AdvanceOutcome
    public var needsFrame: Bool { get }
    public var wantsQuit: Bool { get }
    public var size: Size { get }
}

public struct AdvanceOutcome: Sendable {
    public var produced: Bool     // false = clean, nothing emitted
    public var followUp: Bool     // schedule another advance soon
}
```

Emission stays per-backend (ANSI diff, HTML, DrawList bytes, CG) — the
`emit` closure receives the painted buffer; no backend forks layout, paint
order, or the dirty gate ever again.

### D3. Migration (one slice per backend, each gated)

1. Introduce `HostPump` + `HostPumpTests` (portable: eager-resize
   semantics, clean-skip, follow-up flag, quit propagation, buffer reuse).
2. `AppRuntime.run()` rewires to `HostPump` (loop keeps timeout/idle
   logic); TUI resize becomes eager; update pinned tests.
3. `GamaWASM`, `GamaEmbed` rewire (behavioral no-op; their tests must not
   change — that is the proof the canonical shape matches them).
4. `GamaHostView` / `GamaAppleShell` rewire; AppleUI resize becomes eager;
   shell multi-window tests re-run unchanged except resize timing.
5. ADR 0007 superseded; new ADR "one pump, eager resize"; backend guides
   drop their per-backend resize-timing warnings.

Out of scope: frame pacing/vsync policy, damage regions, partial repaints.
Every slice merges only on a green six-job matrix.
