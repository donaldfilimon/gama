# Gama umbrella — frame-pump unification and resize policy (Slice C, wave 2)

Date: 2026-08-27. Status: **implemented** by the canonical `HostPump` and ADR
0008. Delivery evidence is maintained in `docs/Capabilities.md`.

Supersedes the interim decision of `docs/adr/0007-frame-pumps.md`; ADR 0007 is
Superseded and ADR 0008 records the final shape.

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

### Implementation note (2026-08-27) — D2 is split across two modules

D2 as written cannot compile. It places `HostPump` in GamaCore while giving
`advance` an `emit: (borrowing CellBuffer)` closure, but `CellBuffer` lives
in **GamaDraw**, and `Package.swift` has GamaDraw depending on GamaCore, not
the reverse. The intent (one dirty gate, one resize policy, one paint order)
is preserved by splitting the type across the dependency edge:

- **`Sources/GamaCore/HostPump.swift`** — the policy. Owns the consumed
  `FrameHost` and `size`, implements eager resize in `handle(_:)`, and
  exposes `advance() -> AdvancedFrame?` carrying the laid-out node and the
  `followUp` flag. Stdlib-only, so the policy stays inside the Embedded
  proof — `check-embedded.sh` compiles GamaCore alone, so a pump living in
  GamaDraw would have fallen outside it entirely.
- **`Sources/GamaDraw/HostPump+CellBuffer.swift`** — the buffer path, as an
  extension: `advance(into:emit:) -> AdvanceOutcome` doing
  resize-if-needed → `clearBack` → `CellPainter.paint` → `emit`.

Rejected alternative: inverting the dependency behind a GamaCore protocol
that `CellBuffer` conforms to. Its only conformance would live in GamaDraw,
and it adds existential/generic machinery to a module with a
"no existentials in hot paths" rule.

**A fifth duplicated fragment, unnamed in the table above, is folded in
here:** buffer resizing. GamaEmbed resized the buffer on the `.resize`
event; GamaAppleUI compared `buffer.size` against the grid on every draw.
Both are now `CellBuffer.resizeIfNeeded(_:)`, which normalizes *before*
comparing — a plain `size != newSize` check is wrong, because `size` holds
the normalized extent, so any request above `maximumCellCount` never
compares equal and would re-allocate and force a full present on every
frame.

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
