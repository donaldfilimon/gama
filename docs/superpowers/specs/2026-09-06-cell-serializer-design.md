# `CellSerializer`: naming the wholesale buffer consumers

Successor to the phase 5 that
[`2026-09-06-adaptive-terminal-surface-design.md`](2026-09-06-adaptive-terminal-surface-design.md)
closed unbuilt. That phase proposed conforming `GamaWASM` and `GamaEmbed` to
`CellPresenter`; this design explains why that was impossible, and names the
family those two backends actually belong to.

This is a design record, not a capability claim. Nothing here is implemented.

## Why `CellPresenter` cannot span these backends

`CellPresenter` (`Sources/GamaDraw/StreamPresenter.swift`) declares:

```swift
mutating func present(_ buffer: inout CellBuffer) -> Output
```

and its documentation promises the method "reconciles `buffer`'s back frame
against its front frame, emits the result for this consumer, **and swaps the
buffers**." Both halves of that contract fail for the wholesale backends.

The buffers are not swapped. Grepping `Sources/GamaWASM` and
`Sources/GamaEmbed` for `presentDiff` or a buffer swap returns nothing; the
only `swap` in either is `swap(&fg, &bg)` in `HTMLSerializer.css(for:)`, which
implements the `.inverse` text attribute and is unrelated. Neither backend has
ever reconciled a front plane against a back plane. They read the freshly
painted back plane whole, every frame.

The `inout` access cannot be formed. Both backends reach the grid through
`HostPump.advance(into:emit:)`
(`Sources/GamaDraw/HostPump+CellBuffer.swift:28`):

```swift
public mutating func advance<E: Error>(
    into buffer: inout CellBuffer,
    emit: (borrowing CellBuffer) throws(E) -> Void
) throws(E) -> AdvanceOutcome
```

The consumer receives a **borrow**. No `inout` argument can be produced from
it, so a `CellPresenter` conformance on either backend would have had zero call
sites even if its swap contract had been honest.

These are not two flaws in one protocol. They are one fact stated twice: the
wholesale consumers derive a value from a buffer they do not own and do not
modify, and `CellPresenter` describes a consumer that mutates the buffer it is
given. The families are genuinely different.

## The protocol

In `Sources/GamaDraw/`, beside `CellPresenter`:

```swift
public protocol CellSerializer {
    associatedtype Output

    func serialize(_ buffer: borrowing CellBuffer) -> Output
}
```

Three properties, each a deliberate contrast with `CellPresenter`:

- **Non-`mutating`.** The serializer holds no frame state. `AnsiPresenter` and
  `StreamPresenter` are `mutating` because reconciliation advances the buffer;
  nothing here does.
- **No swap, stated in the doc comment.** The absence of a swap is the load-
  bearing difference, so the documentation must say it rather than leave a
  reader to infer it from the missing `inout`.
- **`borrowing` parameter.** `CellBuffer` is `public struct CellBuffer:
  Hashable, Sendable` — it is `Copyable`. `borrowing` is therefore an intent
  marker and a guarantee that no copy is taken; it is **not** a correctness
  requirement, and the doc comment must not imply otherwise. It also matches
  the `emit` parameter the backends are already handed.

## Conformances

Two, both wrapping code that already exists, neither changing its behavior.

**`DrawListSerializer`** — new, public, `Sources/GamaDraw/`. Forwards to
`DrawList.from(_ buffer: CellBuffer)` (`Sources/GamaDraw/DrawList.swift:35`).
`Output == DrawList`.

**`HTMLSerializer`** — existing, internal, `Sources/GamaWASM/WASMHost.swift`.
`Output == String`. It is currently a caseless `enum` with static methods, so
it becomes a `struct` to have an instance to conform with. Its serialization
logic, including the run-merging and the escaping rules documented on
`escape(_:)`, is copied verbatim, not rewritten.

The asymmetry is deliberate and worth recording: `DrawListSerializer` is public
in GamaDraw because `DrawList` is a public output format, while
`HTMLSerializer` stays internal to GamaWASM because its HTML is a private
detail of that backend's DOM contract.

## What does not move

Delivery stays exactly where it is. Only the derivation is routed through the
protocol.

```swift
// Sources/GamaWASM/WASMHost.swift:69   — the gama_js_setHTML call stays here
// Sources/GamaEmbed/CInterface.swift:33 — the `encoded =` assignment stays here
```

In both, the closure body changes from calling a free function to calling
`serializer.serialize(painted)`. `advance(into:emit:)` is not touched. No
buffer is swapped, because neither backend ever swapped one. No error channel
is added: both derivations are total, so `serialize` does not throw, and the
existing typed-throws `throws(E)` on `advance` is untouched.

## Rejected: a third conformance

An earlier draft of this design proposed `AccessibilitySnapshot` as a third
member, on the reasoning that it is also a buffer-rooted derivation. Checking
the call sites refuted this before anything was built.

`AccessibilitySnapshot` has exactly one production consumer,
`Sources/GamaAppleUI/GamaHostAccessibility.swift:28`, which derives it from
`currentDrawList` — a **retained view's** DrawList, not a borrowed `CellBuffer`
inside `advance(into:emit:)`. GamaAppleUI is precisely the backend the phase 5
spike excluded, because it mutates a retained view rather than producing an
output value. `Sources/GamaWASM` contains no Swift accessibility path at all;
the accessibility assertion in the WASM gate lives in the browser driver
`scripts/browser-runtime-smoke.mjs`, not in Swift.

Adding an `AccessibilitySerializer` would therefore have created a type with
zero call sites. That is the exact defect this repository has already recorded
against `AnsiPresenter`, which "had no production call site when it shipped,
which made the protocol a claim rather than a seam." Two conformances that are
both load-bearing beat three where one is decorative.

## Testing

The real check is that both outputs stay byte-identical. A serializer that
changes one byte of HTML breaks the WASM gate's `state=0->0->1` browser marker;
one that changes the DrawList encoding breaks `check-c-abi.sh`. Those gates
already exist and must pass unchanged.

Added coverage pins the wrappers as behavior-preserving rather than assuming
it: for each conformance, one Swift Testing case asserting that
`serializer.serialize(buffer)` equals the free function it wraps, over a
painted multi-row buffer with mixed styles. Without these, a future edit could
change a wrapper and be caught only by a browser smoke, which reads as an
unrelated failure.

## What this buys, and what it does not

It buys one thing: the two wholesale consumers read as one named family, and
the difference from `CellPresenter` is enforced by a signature rather than
asserted in a comment.

It does not buy runtime selection. Nothing chooses a serializer at startup —
GamaWASM always emits HTML and GamaEmbed always emits DrawList bytes. This
protocol is a name for a shape, accepted as such. If a consumer that must
select an output ever appears, this is the seam it would use, but that consumer
is not asserted here.

The cost is not zero. GamaWASM is hosted proven, so this change requires the
full six-job acceptance matrix to re-prove a benefit that is documentation
rather than capability. That trade was made deliberately and is recorded here
so a later reader does not have to reconstruct it.

## Open questions

None blocking. The scope above is closed: two conformances, no error channel,
no runtime selection, delivery unmoved.
