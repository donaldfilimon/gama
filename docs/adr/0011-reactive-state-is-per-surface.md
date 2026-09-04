# 0011 — @Reactive state is per-surface

Status: Accepted.

Implements
[`../superpowers/specs/2026-08-29-view-state-identity-design.md`](../superpowers/specs/2026-08-29-view-state-identity-design.md)
(approved 2026-08-29), with the spec's one open implementation question
resolved by measurement below. Delivery evidence is maintained in
`../Capabilities.md`.

## Context

A scene's content closure runs on every frame, and `@Reactive` used to store
its `Signal` in the component *instance*. A component constructed inline
inside a `Window` body was therefore a fresh value with fresh signals every
frame: a press mutated the current instance, the host went dirty, and the
next pump painted a new instance at its declared defaults. Measured
2026-08-27, an inline `@Reactive` counter reported the action ran while the
frame still read `count 0`. Nothing detected it — no diagnostic, no test —
the control simply looked inert.

The only mitigation was prose: hoist the instance so it outlives the closure.
Hoisting was incomplete as well as manual. It stores state per *scene
declaration*, not per *surface*: every window of a `WindowGroup` captures the
same closure, so a hoisted instance was one shared instance behind all of
them. That is right for deliberately shared model state and wrong for
per-window state, for which the framework offered nothing.

A second, latent defect sat underneath. `count += 1` produced a frame only
because `handle` set the dirty flag unconditionally after invoking an
action; the host never observed the component's signal. An out-of-band write
— a timer, a lifecycle handler — painted nothing unless the author also
called `observe()`.

## Decision

**`@Reactive` state moves from the component instance to the owning
`FrameHost`, keyed by structural identity.** The contract is two words:
**`@Reactive` is per-surface; a `Signal` on the `App` is shared.**

- `@Reactive var x: T = v` expands to a `private let _x: ReactiveSlot<T>`
  peer (`Sources/GamaCore/ReactiveState.swift`) instead of a `Signal<T>`.
  `@Component` synthesizes `render(in:)`, which calls
  `_x._bind(in: context, slot: i)` for each `@Reactive` property in
  declaration order and then renders `body` under `context.child(0)` —
  the same shape as the default `View.render`.
- Binding resolves the slot's `Signal` from the host's `HostStateStore`
  (package-internal, a `final class` owned exactly like `HostActionStore`),
  keyed by `(context.id, slot index)`. A fresh instance each frame binds to
  the same host-owned signal, so `Button("+1") { count += 1 }` — which
  captures a copy of the struct and therefore a copy of the slot reference —
  writes to storage that outlives the instance. Two windows of one
  `WindowGroup` resolve independent signals for the same slot.
- Every host-owned signal observes the host's dirty flag. The observer
  captures the dirty signal, never the store, so there is no cycle. An
  out-of-band write to bound `@Reactive` state sets `needsFrame` without
  `observe()`; this closes the latent defect above.
- A hoisted instance still works. When one instance is rendered by several
  hosts, `FrameHost` calls `stateStore.activate()` before invoking an action
  or key handler so each host re-attaches its own bindings and the write
  lands in the invoking host's storage. The instance's pre-render local value
  seeds each surface's initial value, so `let c = Counter(); c.count = 5`
  before the first frame is preserved.
- `pump` may build twice for focus reconciliation; the store marks per build
  and sweeps once after the final build. Keys the final build did not resolve
  are evicted and their invalidation observers cancelled. Branch flips and
  positional `ForEach` reorders drop state (SwiftUI-equivalent);
  `IdentifiedForEach` and the new `.stateScope(_ id: NodeID)` modifier
  (`StateScopedView`, which replaces the inherited identity for its subtree
  exactly as `IdentifiedForEach` does per element) are the escape hatches.
- Erasure is `AnyObject` plus an `ObjectIdentifier(Signal<Value>.self)`
  type-id check and `unsafeDowncast` — the spec's simpler first option. The
  spec named `check-embedded.sh` as the arbiter and the `ScenePayload`-shaped
  form as the fallback; the simple form passed, so the fallback was never
  needed.
- What stays instance-local: host-less rendering (`BuildContext()` with no
  store, as `gama-demo --emit-mlir` uses) keeps the slot on its own local
  signal, and `State<Value>` is unchanged.
- Raw `Signal` stored properties inside components are unsupported by
  decision. The demo's `name` and `notifications` became `@Reactive`, and
  `TextField`/`Toggle` take `_name.binding()`; `ReactiveSlot` exposes
  `signal`, `get()`, `set(_:)`, `binding()`, and `_bind(in:slot:)` so a slot
  can *produce* a signal for controls, not merely get and set a value.
- `ReactiveSlot` (public) and `HostStateStore` (package) declare `~Sendable`
  with the unavailable `@unchecked Sendable` extension and join the ADR
  [0009](0009-signal-is-not-sendable.md) confinement table: a slot belongs to
  the host that bound it.

### Diagnostics

Silence was the bug, so every way the binding can be skipped is loud.

- Compile time, in `GamaMacrosImpl`: `@Reactive` outside a struct marked
  `@Component` — including in a class — is error `reactive.requires-component`
  ("@Reactive requires a struct marked @Component; elsewhere its state never
  binds to a host"), detected through `MacroExpansionContext.lexicalContext`
  and skipped, never guessed, when the context carries no lexical
  information. A hand-written `render(in:)` beside `@Reactive` properties is
  error `component.render-collision`, and synthesis is skipped rather than
  silently dropping the binding.
- Runtime: `FrameHost.transientStateIDs: [NodeID]` (public, mirroring
  `duplicateIDs`) lists nodes whose reactive storage identity changed since
  the previous frame. It is empty for the inline shape — the spec's stage-2
  acceptance bar — and names the node when a branch flip or a type change at
  the same position reconstructed state.

## The behavior flip, argued

A hoisted `@Reactive` component behind a `WindowGroup` goes from
shared-across-windows to per-window. This is the one semantic change visible
to source, and it is deliberate:

- Per-surface is what a window author expects. A counter in a document
  window that ticks in every other document window is a bug report, not a
  feature.
- Sharing keeps an explicit spelling. A `Signal` stored on the `App` is one
  instance behind every surface, exactly as before, and the host observes it
  through `observe(_:)`. `SceneTests.sharedModelIndependentHosts` pins that
  boundary and is untouched and green.
- The old sharing was documented as a limitation, never as a goal: the
  `@Reactive` doc comment and `CLAUDE.md` described it as sharing rather
  than per-surface storage, with the per-window gap tracked as open work.
  No in-repository code relied on it.

## Verification

- `Tests/gamaTests/ViewStateIdentityTests.swift` (8 tests): inline
  persistence with an empty transient list, independent `WindowGroup`
  surfaces, a hoisted instance writing per surface with the pre-render seed,
  branch-flip eviction back to a `reactiveStateCount` baseline of zero,
  out-of-band write invalidation without `observe()`, `transientStateIDs`
  naming the reconstructed node, `.stateScope` keeping state across an
  insertion, and host-less rendering staying local.
- `ReactiveStateLifetimeTests` (the hoisted shape) pass unchanged.
  `SceneTests.sharedModelIndependentHosts` passes unchanged.
  `MacroExpansionTests` is rewritten to pin the slot expansion, the
  synthesized `render(in:)`, and both new diagnostics.
- `Tests/CompileFail/ReactiveSlotSendable.swift` joins
  `scripts/check-concurrency-negative.sh`'s fixture array (three fixtures);
  `scripts/check-boundaries.sh` requires both `~Sendable` declarations and
  both unavailable conformances in `Sources/GamaCore/ReactiveState.swift`.
- Locally proven 2026-09-04: 266 tests in 49 suites, `check-boundaries.sh`,
  `check-concurrency-negative.sh`, and `check-embedded.sh` green.
- Embedded cost, measured the same day: the relocatably linked artifact is
  631,960 bytes on this branch against 584,684 bytes on `origin/main`,
  +47,276 bytes (+8.1%). The identity store is the cost.
- `gama-demo --emit-mlir` output is byte-identical to `origin/main` (185
  lines): the host-less path is unchanged.

## Consequences

- Source breaks, permitted pre-release as `../SceneMigration.md` established:
  `@Reactive`'s `_`-prefixed peer changed type from `Signal<T>` to
  `ReactiveSlot<T>` (in-repository blast radius was `MacroExpansionTests`);
  `@Component` now declares `names: named(init), named(render)`; the two
  compile errors above reject code that previously compiled and silently
  lost state; and hoisted `@Reactive` behind a `WindowGroup` flips from
  shared to per-window, with no in-repository user.
- No migration is required for `Window`: hoisting remains valid, and inline
  construction is now the primary shape.
- Escape hatches for identity: `IdentifiedForEach` and `.stateScope(_:)`.
  Structural keys are sensitive to source edits above a subtree, as focus and
  action identity already were.
- `State<Value>` is unchanged and instance-local.
- The Embedded core grows by the store, recorded in `../Capabilities.md`.
- Evidence level is **Locally proven**. Hosted proof arrives with the
  hosted matrix on the merged commit. The second-backend proof uses the
  public author-facing form: `gama-web-demo` declares an inline `@Component`
  with `@Reactive` state, the Node smoke requires the exact `0` to `1`
  transition after Enter, and the browser smoke requires `state=0->0->1` so
  only Enter can account for the mutation. The Android demo uses the same
  macro-authored form; its dual-ABI cross-build and API 36 emulator assertion
  from `Tapped 0` to `Tapped 1` are the third-backend proof.
