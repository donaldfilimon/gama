# View-state identity

Status: Implemented and locally verified 2026-09-04 (ADR 0011,
`../../adr/0011-reactive-state-is-per-surface.md`). Approved 2026-08-29. Promotes
`drafts/2026-08-27-view-state-identity-draft.md` out of `drafts/`; that draft
holds the original investigation and is superseded by this document.

## Problem

A scene's content is a closure the host re-evaluates on every render.
`Window._collectScenes` (`Sources/GamaCore/Scene.swift:211-214`) builds:

```swift
makeRender: { payload in
    guard payload == nil else { return nil }
    return { context in content().render(in: context) }
}
```

`content()` runs per `renderScene` call. `@Reactive` stores its `Signal` in the
**component instance** (`Sources/GamaMacrosImpl/Plugin.swift`, `ReactiveMacro`).
So a component constructed inline inside a `Window` body is a fresh value with
fresh signals every frame.

The consequence is silent data loss. A press invokes the action, which mutates
the *current* instance's signal and marks the host dirty; the next pump builds a
**new** instance at its declared defaults and paints that. Measured 2026-08-27:
an inline `@Reactive` counter reports the action ran while the painted frame
still reads `count 0`. Pointer presses lose state identically — this is not
keyboard-specific.

Nothing detects it. There is no diagnostic, no warning, and no failing test; the
control simply looks inert. The only mitigation today is prose telling authors
to hoist the instance so it outlives the closure (`CLAUDE.md`, "State lifetime
trap"; `Sources/GamaDemo/main.swift:132` does exactly that).

**Hoisting is also not a complete answer.** It stores state per *scene
declaration*, not per *surface*. Every window of a `WindowGroup` captures the
same closure, so a hoisted instance is one shared instance behind all of them.
That is correct for deliberately shared model state and wrong for per-window
state, for which the framework provides nothing.

### A second, latent defect

`count += 1` produces a frame only because `handle` sets `dirty` unconditionally
after `actions.invoke` (`Sources/GamaCore/FrameHost.swift:281-300`). The host
never observes the component's `Signal`. An out-of-band mutation — a timer, or
`handleLifecycle` — therefore paints **nothing** today.
`SceneTests.sharedModelIndependentHosts` has to call `observe()` explicitly.
This design closes that for free, and the spec treats it as in scope rather than
a happy accident.

## Goals

- An inline-constructed component keeps its `@Reactive` state across frames.
- `@Reactive` is **per surface**: two windows of one `WindowGroup` get
  independent state, with no new author-facing mechanism.
- The failure becomes detectable rather than silent.

## Non-goals

- No change to `Signal`'s observation API, storage, or FNV identity path.
- No synchronization primitives in `GamaCore`.
- Not a general dependency-tracking or diffing engine. The retained render model
  and per-frame rebuild (ADR 0008) are unchanged; only *where the signal lives*
  moves.

## Constraints this design must satisfy

These are checked, not assumed:

- **`GamaCore` is stdlib-only and Embedded-safe.** `scripts/check-boundaries.sh`
  rejects any import of Foundation, AppKit, UIKit, Darwin, Glibc, WinSDK, or
  Synchronization in `GamaCore` and `GamaPlugin`, and rejects process-global
  registries **anywhere**. Its grep is literally
  `ActionRegistry|Invalidator\.shared|nonisolated\(unsafe\).*_host`, so no new
  type may be named `…Registry` regardless of how it is implemented.
- **`Signal` is non-`Sendable` with an unavailable conformance** (ADR 0009,
  `Sources/GamaCore/State.swift:179-180`). The new store and slot are likewise
  non-`Sendable` and join that ADR's confinement table. Nothing is laundered
  across isolation.
- **`pump` can call `renderScene` twice in one frame** (focus reconciliation,
  `FrameHost.swift:117-190`). Any mark/sweep must sweep **once, after the final
  build** — the reconciliation build is the one that paints, so its marks win.
- **Each `FrameHost` uniquely owns its state** (ADR 0006, `~Copyable` hosts).
  Per-host storage is where identity-keyed state belongs; this design follows
  that record rather than arguing with it.

## The precedents this reuses

The draft's largest open question was whether per-host keyed storage survives
`check-embedded.sh`. It already does, twice over — neither mechanism is new:

- **`FrameHost` already owns exactly this shape.**
  `private let actions = HostActionStore()` (`FrameHost.swift:52`), a
  `final class` holding `var actions: [NodeID: () -> Void]` with a
  `beginBuildPass()` that clears per build (`:11-25`). It passes
  `check-embedded.sh` today.
- **`ScenePayload` already does typed erasure in `GamaCore`** with
  `ObjectIdentifier(Value.self)` plus `UnsafeMutableRawPointer` and
  `assumingMemoryBound`, no dynamic cast (`Scene.swift:407-437`).
- **`BuildContext` already threads host-closing closures** —
  `registerAction` / `registerKeyHandler` (`View.swift:22-33`). Threading a
  state store is the same seam.
- **`IdentifiedForEach` already overrides `childContext.id`**
  (`View.swift:302`). Stage 3 follows that idiom rather than inventing one.

## Design

State moves from the component instance to the host, keyed by
`(NodeID, slot index)`. `@Reactive` stops owning a `Signal` and starts owning a
**slot** that resolves one from the host store at render time.

The crux, and the reason this fixes the bug: `Button("+1") { count += 1 }`
captures a copy of the component struct, which copies the **slot reference**.
When the action fires a frame later, that slot still points at the host-owned
signal, so the write lands in host storage. The next pump builds a fresh
instance with a fresh slot, binds it to the *same* host signal, and paints the
mutated value. Stale actions cannot fire against evicted state, because
`actions.beginBuildPass()` already clears the action table each build.

### Delivered in three stages

Each stage is independently mergeable and independently green.

**Stage 1 — the diagnostic.** `FrameHost.transientStateIDs: [NodeID]`, mirroring
the existing `duplicateIDs` mechanism (`FrameHost.swift:58` declaration, `:171`
computation) — a mechanism with established test precedent in
`FormControlTests` and `PluginSlotTests`. A `@Component` with `@Reactive`
storage reports its storage identity per build; a `NodeID` presenting a
*different* storage object on consecutive builds is being reconstructed and
losing state.

This is worth landing alone: it converts a silent correctness bug into a
loud, testable one. It is also stage 2's acceptance criterion — **stage 2 is
correct when `transientStateIDs` is empty for the inline shape**, which is a
measurable bar rather than a subjective one.

Note what deliberately is *not* attempted: a **compile-time** diagnostic for
"component with `@Reactive` state constructed inside a scene closure" is not
implementable. A macro cannot resolve whether `Foo()` inside a `@ViewBuilder`
closure names a type carrying `@Reactive` — that is cross-file type information
macros do not have — and a syntactic heuristic would flag `Text(...)` and every
other construction. The runtime check is the only precise one.

**Stage 2 — the host store.** A `HostStateStore` owned by `FrameHost`, resolved
through `BuildContext`, with `@Reactive` holding a slot that binds to it.

- Erasure mirrors `ScenePayload` rather than using `AnyObject`: store
  `ObjectIdentifier(Value.self)` plus a retained opaque reference, retrieved
  after a type-id check. Try plain `AnyObject` + `unsafeDowncast` first because
  it is far simpler; **`check-embedded.sh` is the arbiter**, and the
  `ScenePayload`-shaped form is the fallback that is structurally identical to
  already-proven code.
- `BuildContext` gains `stateStore` defaulting to `nil`, inherited unchanged by
  `child(_:)`. A `nil` store means instance-local storage, which keeps the
  host-less path working — `gama-demo --emit-mlir` renders through
  `BuildContext(id: .root)` with no host at all, and `check-mlir.sh` must
  produce identical IR.
- `resolve` subscribes each created signal to the host's invalidation, which is
  what closes the latent out-of-band defect above.
- `bind` seeds the store on first resolution with the slot's **current local
  value**, not the declared default, so `let c = Counter(); c.count = 5` before
  first render is preserved.
- No retain cycle: store → `Signal`; the signal's observer captures the host's
  `dirty` signal, never the store.

**Stage 3 — `.stateScope(_:)`.** Explicit identity for the cases where
structural keying is genuinely wrong: `ForEach` reorders, and source edits that
must preserve state. Structural keys are sensitive to source edits — every
modifier wrapper descends `context.child(0)` (`Primitives.swift:531,552,581,613,634,650`),
so inserting `.padding()` shifts a subtree's `NodeID`. Focus and action identity
already have exactly that sensitivity, so this is not a new class of fragility,
but it needs an escape hatch.

### Raw `Signal` properties are converted, not wrapped

`CounterPanel` holds `name` and `notifications` as raw `Signal`s driving
`TextField`/`Toggle` bindings (`Sources/GamaDemo/main.swift:46-47`). No
`@Reactive`-only fix reaches them, so inline construction would still lose them
— a second silent-state-loss shape, which is exactly what this work exists to
remove.

**Decision: convert them to `@Reactive` and treat raw `Signal` properties inside
components as unsupported.** This imposes a requirement on stage 2:
`TextField`/`Toggle` bindings need a real `Signal`, so a `@Reactive` slot must
be able to *produce* one for binding, not merely get/set a value. That is a
constraint on the slot's API, and the implementation plan must satisfy it rather
than discover it.

## What breaks

Pre-release source breaks are permitted here when argued and documented — the
`App.content` → scenes migration set that precedent (`docs/SceneMigration.md`).

1. **`@Reactive`'s `_`-prefixed peer changes type** from `Signal<T>` to a slot.
   In-repo blast radius is exactly one file:
   `Tests/gamaTests/MacroExpansionTests.swift:174-186`, which pins the expansion
   text verbatim and must be rewritten — which is also the right place to pin
   the new shape.
2. **`@Component` synthesizes `render(in:)`.** A component that hand-writes one
   collides; detect syntactically, skip synthesis, and emit a diagnostic rather
   than silently dropping reactive state.
3. **`@Reactive` on a `class`, or in a struct without `@Component`,** never binds
   and silently keeps instance-local storage. This must be a diagnostic, not
   silence — silence is the bug being fixed.
4. **Behavior flip: a hoisted `@Reactive` component behind a `WindowGroup` goes
   from shared-across-windows to per-window.** This is the deliberate, source-
   visible change and it **must be argued in an ADR**, not assumed.
   `SceneTests.sharedModelIndependentHosts` is the pinned boundary that keeps
   raw-`Signal`-on-the-`App` sharing intact, and it must stay green untouched.
   The resulting contract is two words: **`@Reactive` is per-surface; a `Signal`
   on the `App` is shared.**
5. Branch flips and `ForEach` reorders drop state (SwiftUI-equivalent);
   `IdentifiedForEach` and stage 3 are the escape hatches.

## Testing

The inverse of the current pin is the headline test:
`Window("Counter", id: "main", role: .primary) { MacroCounter() }` — constructed
**inline** — press, pump, assert the painted frame reads `count 1`. That fails
today by measurement, and it is the whole bug.

Also required: both existing `ReactiveStateLifetimeTests` (the hoisted shape)
stay green **unchanged**; two hosts from one `WindowGroup` descriptor get
independent counters while `sharedModelIndependentHosts` still passes; branch-
flip eviction returns the store to baseline (leak proof); the host-less path
keeps instance-local storage so `MacroUsageTests.macroSurface` stays green; an
out-of-band mutation sets `needsFrame`, proving auto-subscription; and
`MacroExpansionTests` is rewritten to the new expansion.

## Gates

`check-apple.sh` is primary — the only gate that runs `swift test`, so every
test-level consequence is invisible to the other twelve. `check-embedded.sh` is
the primary *risk* gate: it compiles `GamaCore` alone for armv7em and settles
the erasure question, printing the artifact byte delta.
`check-boundaries.sh` enforces the import and process-global rules and must keep
the Signal-confinement fixtures typechecking — the store must not gain
`Sendable`. `check-mlir.sh` proves the host-less `stateStore == nil` path yields
identical IR. `check-wasm.sh` and `check-android-emulator.sh` provide behavioral
proof on a second and third backend. `check-doc-coverage.sh` and
`check-docs.sh` cover the new public declarations and the documentation
inversion below. Add a `Tests/CompileFail/` fixture pinning the store and slot
as non-`Sendable`.

## Documentation inversion

The expensive part is not the code. The blessed pattern **flips**: inline
construction becomes correct, hoisting becomes legacy-but-valid. Every place
that currently teaches the opposite must change in the same PR that lands stage
2 — `CLAUDE.md`'s "State lifetime trap", the `@Reactive` doc comment
(`Sources/GamaMacros/Macros.swift:40-58`),
`Sources/GamaCore/GamaCore.docc/CompositionAndState.md`, `docs/Testing.md`, the
fixture comments in `Tests/gamaTests/MacroUsageTests.swift`, and the hoisting
comment in `Sources/GamaDemo/main.swift`. Plus a new ADR, a row in
`docs/adr/0000-index.md`, a note in `docs/SceneMigration.md`, and a
`docs/Capabilities.md` row once the gate passes.

External migration cost is **none required**: hoisting stays correct for
`Window`. The only semantic flip is `WindowGroup` + hoisted `@Reactive`, which
has no in-repo user.
