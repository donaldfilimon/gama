# State, identity, and lifetime

Status: Current behavior guide. `@Reactive` state is identity-keyed and
host-owned per surface — Locally proven on 2026-09-04 (Apple gate,
boundaries, concurrency negatives, Embedded compile/link). Hosted proof
arrives with the merge. Design:
[2026-08-29-view-state-identity-design.md](superpowers/specs/2026-08-29-view-state-identity-design.md);
decision: [ADR 0011](adr/0011-reactive-state-is-per-surface.md).

Gama rebuilds view content into a retained render tree on every frame. A
component value built inside a scene closure is a fresh instance each frame;
its `@Reactive` state is not, because the owning `FrameHost` stores it under
the node's structural identity. The distinction between view identity,
component-instance lifetime, and host lifetime is still part of the public
programming model: it decides what is shared, what is per surface, and what
is dropped.

## The three lifetimes

| Lifetime | Identity | Typical owner | Examples |
| --- | --- | --- | --- |
| Application | The `App` value | shell or runtime | shared `Signal` models, services, hoisted components |
| Surface host | `SceneID` + `WindowInstanceID` | backend or `GamaAppleShell` | focus, actions, subscriptions, dirty state, `@Reactive` storage |
| Render node | structural `NodeID` for one frame path | `BuildContext` | focus reconciliation, hit testing, `ForEach` children, `@Reactive` slot keys |

A component instance may be application-owned, surface-owned by application
code, or ephemeral inside a scene closure. `State` follows that instance.
`@Reactive` follows the surface host and the node the component renders under.

## Persistent state: build inline

This is the correct shape. `CounterPanel` is a new value on every rebuild, and
its `@Reactive` properties keep their values anyway:

```swift
@Component
struct CounterPanel {
    @Reactive var count: Int = 0

    var body: some View {
        Button("count \(count)") { count += 1 }
    }
}

struct CounterApp: App {
    init() {}

    var scenes: some Scene {
        Window("Counter", id: "main", role: .primary) {
            CounterPanel() // Fresh instance each frame; state persists.
        }
    }
}
```

`@Reactive var count` expands to a `private let _count: ReactiveSlot<Int>`
peer, and `@Component` synthesizes `render(in:)` to call
`_count._bind(in: context, slot: 0)` — one call per `@Reactive` property, in
declaration order — before rendering `body`. Binding resolves the host's
`Signal` for the key `(context.id, slot)` from a per-host store that
`FrameHost` owns. A fresh instance at the same position binds to the same
signal, so state survives the rebuild. The repository demo
(`Sources/GamaDemo/main.swift`) builds `CounterPanel()` inline.

**Per surface.** The store belongs to the `FrameHost`, and every live surface
owns one host, so two windows of one `WindowGroup` resolve independent state
for the same declaration. The contract in two words: **`@Reactive` is
per-surface; a `Signal` on the `App` is shared.**

**Hoisting is still valid.** An instance stored on the `App` and rendered by
several hosts is bound per surface too: each host re-attaches its own
bindings before invoking an action, so an action on one window writes to that
window's storage. The instance's pre-render local value seeds each surface's
initial value (`let c = Counter(); c.count = 5` before the first frame is
preserved). Hoist for the seed or for a stable owner, not to share state
across surfaces — for that, put a `Signal` on the `App`.

**Host-less rendering** (`BuildContext()` with no host, as in
`gama-demo --emit-mlir` or `component.render(in: BuildContext())` in a test)
never binds; the slot keeps instance-local storage. `--emit-mlir` output is
unchanged by binding.

**Eviction.** After a frame's final build the host sweeps every key that
build did not resolve, so a subtree that stops rendering releases its state
and nothing leaks. Identity is structural, so a branch flip, a positional
`ForEach` reorder, or a different component type at the same position drops
state — SwiftUI-equivalent behavior. Two escape hatches replace the subtree's
identity with one you choose:

- `IdentifiedForEach(_:id:content:)` keys each element by a domain
  identifier.
- `.stateScope(_ id: NodeID)` (`StateScopedView`) pins any view's subtree —
  its `@Reactive` state, focus, and actions — to `id` instead of its
  position. Distinct scopes need distinct ids.

**Diagnostic.** `FrameHost.transientStateIDs` mirrors `duplicateIDs`: after
each frame it lists the nodes whose reactive storage changed identity since
the previous frame. It is empty for a correctly bound tree; a nonempty list
means a component's identity moved and its state was reconstructed.

## `Signal`, `Binding`, `State`, and `@Reactive`

`Signal<Value>` is the reference-backed mutable cell:

- `get()` reads.
- `set(_:)` writes and notifies.
- `update(_:)` performs one in-place mutation and notification.
- `setIfChanged(_:)` suppresses an equal write when `Value: Equatable`.
- `observe(_:)` returns the token needed for explicit cancellation.
- `binding()` exposes a read/write projection without exposing the signal.

`Binding<Value>` is a pair of host-confined accessors. `map(get:set:)`
projects a subvalue, and `constant(_:)` creates a read-only-in-practice
binding whose writes are discarded.

`State<Value>` is the property-wrapper form and is instance-local. `@Reactive`
is macro sugar that generates a `GamaCore::ReactiveSlot<Value>` peer named
`_name` plus accessors. Before a host binds it, the slot reads and writes its
own local signal; once bound, the host's signal takes over. `_name.binding()`
is the projection to hand to `TextField` or `Toggle` — it follows the binding,
so a control created in one frame keeps writing to host storage. `_name.signal`
exposes the signal currently backing the slot.

`@Reactive` requires a struct marked `@Component`; elsewhere (including a
class) the macro reports an error, because the state would never bind to a
host. A `@Component` with `@Reactive` properties may not hand-write
`render(in:)` — that is also an error, since the synthesized one is what
binds. Raw `Signal` stored properties inside a component are unsupported;
convert them to `@Reactive`.

These types are not `Sendable`. They belong to an owning executor/host.
Transferring exclusive ownership is different from sharing; use an explicit
`sending` boundary when an API genuinely transfers a value.

## Invalidation from inside and outside a frame

An action registered during rendering runs through the owning `FrameHost`.
After invocation, the host marks itself dirty, so ordinary button/toggle/text
input does not require a separate observer.

Bound `@Reactive` state invalidates on its own: every host-owned signal
observes the host's dirty flag, so an out-of-band write from a timer or a
lifecycle handler sets `needsFrame` without an explicit `observe()`.

Raw signals owned by the `App` still need the explicit connection:

```swift
let progress = Signal(0)
var host = try FrameHost(app: ProgressApp())

host.observe(progress)
progress.set(1)

if host.needsFrame {
    _ = host.pump(size: Size(width: 80, height: 24))
}
```

Equivalent connection forms are:

```swift
progress.subscribe(in: host.subscriptions)
let binding = progress.binding(in: host.subscriptions)
```

For a source that cannot expose a signal, call `host.invalidate()` when the
source changes. Do not introduce a process-global invalidation registry.

`cancelSubscriptions()` detaches only that host and leaves the context usable
for later observations. Duplicate observations of the same signal instance
are coalesced.

## Collection identity

`ForEach` requires stable application identity when elements can be inserted,
deleted, or reordered. Focus and `@Reactive` state are stored under `NodeID`,
not an array index, so stable identity lets both survive unrelated collection
changes.

Avoid using a transient position as identity:

```swift
// Positional identity shifts after insertion or removal.
ForEach(rows) { row in
    RowView(row: row)
}
```

Prefer a domain identifier:

```swift
IdentifiedForEach(rows, id: { NodeID(raw: $0.id) }) { row in
    RowView(row: row)
}
```

In this example `row.id` is a stable `UInt64`; adapt another domain identifier
to a collision-free `NodeID` instead of hashing a transient position. For a
single view that must keep its state across an insertion above it, use
`.stateScope(_:)` with the same discipline.

Duplicate interactive identities are reported through
`FrameHost.duplicateIDs` after the frame is built, and reconstructed reactive
storage through `FrameHost.transientStateIDs`. A backend may surface either
as a development diagnostic; malformed identity does not become a
process-global crash.

## Multiple windows

Every live surface owns an independent `FrameHost`, so focus, actions,
subscriptions, dirty state, `@Reactive` storage, and frame production are
isolated by default. Application-owned models can still be intentionally
shared.

There are two ownership shapes, and the rule is short: **`@Reactive` is
per-surface; a `Signal` on the `App` is shared.**

1. **Shared model:** the `App` owns one `Signal`/model and multiple windows
   observe it. A change intentionally dirties every subscribed host.
2. **Per-surface state:** every `@Reactive` property, whether the component
   is built inline or hoisted onto the `App`, resolves independent storage in
   each surface's host. Two windows of one `WindowGroup` never share it; a
   hoisted instance only seeds each surface's initial value.

A hoisted `@Reactive` component inside a `WindowGroup` is therefore
per-window storage, not shared state. To share, move the value to a `Signal`
the `App` owns.

## Scene and window identity

- `SceneID` identifies the declaration.
- `WindowGroupKey<Value>` couples a declaration to its payload type.
- `WindowInstanceID` identifies one live surface.
- `Window` reopens/focuses its singleton instance.
- `WindowGroup` addresses an instance by a hashable, sendable payload.

Lifecycle events may carry both the scene and live-instance identity. A host
ignores addressed events for a different surface.

## Concurrency boundary

The portable runtime favors compiler-checked confinement over locks or false
`Sendable` promises:

- `Signal` and `ReactiveSlot` explicitly declare `~Sendable`; the per-host
  state store is confined the same way.
- Their unavailable `@unchecked Sendable` conformances produce a named
  diagnostic when code attempts to use them as ordinarily sendable
  (`Tests/CompileFail/ReactiveSlotSendable.swift` pins the slot's).
- `FrameHost` and `AppRuntime` are `~Copyable` because a copy would share live
  reference state.
- `GamaCore` does not import `Synchronization` or a platform threading module.

If a platform model is actor-isolated, cross that boundary in application or
host-service code and deliver an ordinary value/action to the owning Gama
host. Do not make the renderer itself an authority over the actor or service.

## Delivered design

The host-owned, identity-keyed store, the transient-state diagnostic, and the
`.stateScope(_:)` escape hatch are the implementation of
[2026-08-29-view-state-identity-design.md](superpowers/specs/2026-08-29-view-state-identity-design.md).
[ADR 0011](adr/0011-reactive-state-is-per-surface.md) records the decision
that `@Reactive` is per-surface and why hoisting no longer means sharing.

## Tests to use

Use source identifiers, not `@Suite` display names:

```bash
unset TOOLCHAINS
swiftly run swift test \
  --scratch-path /private/tmp/gama-state-tests \
  --filter ViewStateIdentityTests
swiftly run swift test \
  --scratch-path /private/tmp/gama-state-tests \
  --filter ReactiveStateLifetimeTests
```

`ViewStateIdentityTests` covers inline persistence, `WindowGroup`
independence, hoisted-instance per-surface writes, branch-flip eviction,
out-of-band invalidation, `transientStateIDs`, `.stateScope(_:)` across an
insertion, and host-less local storage. `ReactiveStateLifetimeTests` pins
state across keyboard and pointer activation.

Then run `check-boundaries.sh`, `check-concurrency-negative.sh`, and the full
Apple gate before changing confinement or lifetime semantics. A wrong filter
can exit zero after running no tests, so confirm the final test count.
