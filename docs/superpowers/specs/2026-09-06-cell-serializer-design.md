# `CellSerializer`: naming the wholesale buffer consumers

Successor to the phase 5 that
[`2026-09-06-adaptive-terminal-surface-design.md`](2026-09-06-adaptive-terminal-surface-design.md)
closed unbuilt. That phase proposed conforming `GamaWASM` and `GamaEmbed` to
`CellPresenter`; this design explains why that was impossible, and names the
family those two backends actually belong to.

**Status, corrected 2026-09-06 after an independent design review.** This is
implemented: `CellSerializer` and `DrawListSerializer` in `GamaDraw`, the
`HTMLSerializer` conformance in `GamaWASM`, and call sites in `GamaEmbed`,
`GamaWASM`, and `GamaAppleUI`. Locally gated only — no hosted run covers it.
The review found three factual errors in the first revision of this document;
each is corrected in place below and marked, rather than quietly rewritten.

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
  marker: it makes the parameter non-implicitly-copyable in the callee, while an
  explicit `copy` remains legal. It is **not** a correctness
  requirement, and the doc comment must not imply otherwise. It also matches
  the `emit` parameter the backends are already handed.

## Conformances

Two conformances, **three** call sites. The first revision of this document said
"the two wholesale consumers" and excluded `GamaAppleUI`. That was wrong, and
the review caught it: `Sources/GamaAppleUI/GamaHostView.swift:234` is
`session.pump.advance(into: &session.buffer) { painted in self.currentDrawList
= DrawList.from(painted) }` — the same borrowed buffer, the same non-mutating
`DrawList` derivation, differing from `GamaEmbed` only in where the result is
stored, which this design's own rule puts on the delivery side. The exclusion
had been inherited verbatim from the phase 5 `CellPresenter` spike, whose
grounds were the `inout` access and the swap contract; neither survives a
`borrowing`, non-mutating requirement. `GamaAppleUI` is therefore included, and
that is what gives `DrawListSerializer` more than one production call site.

**`DrawListSerializer`** — new, public, `Sources/GamaDraw/`. Forwards to
`DrawList.from(_ buffer: CellBuffer)` (`Sources/GamaDraw/DrawList.swift:35`).
`Output == DrawList`.

**`HTMLSerializer`** — existing, internal, `Sources/GamaWASM/WASMHost.swift`.
`Output == String`. It becomes a `struct` (a caseless `enum` cannot be
instantiated) but **retains all three static members**, and `serialize` is a
one-line forward to `Self.grid(from:)`. This is a forwarding wrapper, not a
transplant: "copied verbatim" in the first revision was ambiguous between the
two, and the difference matters. Forwarding guarantees byte-identity by
construction and leaves every existing assertion in `WASMSerializerTests`
compiling and running unchanged — rewriting the only HTML tests as part of a
behavior-preserving change would remove the witness exactly when it is needed.
It also keeps `grid`'s unqualified `css(for:)` and `escape(_:)` calls resolving
statically.

A trap worth recording: `HTMLSerializer` is declared **outside** `#if
arch(wasm32)` while its production call site is **inside** it. On macOS neither
`swift build` nor `swift test` type-checks that call, so a broken conversion
passes `check-apple.sh` in full and fails only in `check-wasm.sh`, which needs
the pinned WASM SDK. A green `WASMSerializerTests` is not evidence the call
site compiles.

The asymmetry is deliberate and worth recording: `DrawListSerializer` is public
in GamaDraw because `DrawList` is a public output format, while
`HTMLSerializer` stays internal to GamaWASM because its HTML is a private
detail of that backend's DOM contract.

## What does not move

Delivery stays exactly where it is. Only the derivation is routed through the
protocol.

```swift
// Sources/GamaWASM/WASMHost.swift:76    — the gama_js_setHTML call stays here
// Sources/GamaEmbed/CInterface.swift:39  — the `encoded =` assignment stays here
// Sources/GamaAppleUI/GamaHostView.swift:242 — the currentDrawList store stays here
```

In both, the closure body changes from calling a free function to calling
`serializer.serialize(painted)`. `advance(into:emit:)` is not touched. No
buffer is swapped, because neither backend ever swapped one. No error channel
is added: both derivations are total, so `serialize` does not throw, and the
existing typed-throws `throws(E)` on `advance` is untouched.

## Rejected: a third conformance

An earlier draft proposed `AccessibilitySnapshot` as a third conformance. The
rejection stands, but the **argument has been replaced**: the first revision
argued from call-site count, and the review was right that a type mismatch is
the stronger and unanswerable reason.

`AccessibilitySnapshot.from` takes a **`DrawList`**, not a `CellBuffer`
(`Sources/GamaDraw/AccessibilitySnapshot.swift:77`). It is a DrawList-rooted
derivation and simply cannot satisfy `serialize(_ buffer: borrowing
CellBuffer)` without inventing the composition
`AccessibilitySnapshot.from(DrawList.from(buffer))`, which appears exactly once
in this repository — at `Tests/gamaTests/AccessibilitySnapshotTests.swift:202`,
in a test. A conformance would have to manufacture a call chain that no
production code performs.

The call-site observation is still true and still worth keeping as support:
`AccessibilitySnapshot`'s only production consumer is
`Sources/GamaAppleUI/GamaHostAccessibility.swift:28`, which reads the
already-retained `currentDrawList` rather than a borrowed buffer, and
`Sources/GamaWASM` has no Swift accessibility path — the WASM gate's
accessibility assertion is in `WebHost/gama.js`, reached from
`scripts/browser-runtime-smoke.mjs`. Note this is a *different* question from
whether `GamaAppleUI` conforms: it does, for its `DrawList` derivation. Only
its accessibility derivation is excluded.

Adding an `AccessibilitySerializer` would therefore have created a type with
zero call sites. That is the exact defect this repository has already recorded
against `AnsiPresenter`, which "had no production call site when it shipped,
which made the protocol a claim rather than a seam." Two conformances that are
both load-bearing beat three where one is decorative.

## Testing

**Corrected after review; the first revision made two false evidence claims,
which in this repository is the failure the whole evidence policy exists to
prevent.** It asserted that a one-byte HTML change breaks the WASM browser
marker and that a DrawList encoding change breaks `check-c-abi.sh`. Verified
directly, neither holds:

- The browser marker reads `root.textContent` through a regex plus
  `.includes()` (`WebHost/gama.js:174-196`). Span structure, the `gama-row`
  class, and every value emitted by `css(for:)` are invisible to it. A total
  rewrite of `css(for:)` would pass.
- `Examples/CEmbed/main.c:8` asserts `length >= 20` and then checks the four
  magic bytes `GAMA`. So it does catch a magic or truncation change — the
  review overstated this by saying magic is unchecked — but it validates **no
  draw command**, so a change to the command encoding passes.

Nothing pinned byte-identical HTML at all: `WASMSerializerTests` uses
`hasPrefix`, `hasSuffix`, `contains`, and range counts, never whole-string
equality.

The real guards, therefore, are the tests, and they had to be written rather
than assumed. `CellSerializerTests` pins five things: that
`DrawListSerializer.serialize` equals `DrawList.from`; that the instance
`HTMLSerializer.serialize` equals the static `grid(from:)` it forwards to;
that `HTMLSerializer` output matches an **exact literal string**, closing the
gap above; that serializing twice leaves the planes unswapped, so a
`StreamPresenter` still sees every painted row as changed; and that
serialization is repeatable on an unchanged buffer.

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

The cost is not zero, but the first revision misstated it. Every PR pays the
six-job matrix — `main` requires all six as strict status checks — so that is
not a cost specific to this change. The real obligation is narrower and
bookkeeping: the WebAssembly row in `docs/Capabilities.md` is hosted proven
against a specific merge commit, and touching `GamaWASM` invalidates that
recorded evidence until a new green merge re-establishes it.

## Open questions

One, left open honestly. Nothing in the tree is generic over `CellSerializer`:
both conformances are consumed as concrete types, so the protocol constrains
its *conformers'* signatures but no call site is expressed in terms of it.
Deleting the protocol and keeping the two structs would compile. The review
called this the `AnsiPresenter` defect relocated one level up, and that
criticism is fair on its own terms. What answers it partly is the third call
site: `DrawListSerializer` is now used by both `GamaEmbed` and `GamaAppleUI`,
so the family is not a one-member curiosity. What would answer it fully is a
consumer generic over `CellSerializer`, and none is asserted here.

Not open, and deliberately so: no error channel, no runtime selection, no
delivery moved, and no ADR — this changes no settled decision, it names an
existing shape.
