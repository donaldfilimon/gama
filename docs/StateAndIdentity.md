# State, identity, and lifetime

Status: Current behavior guide. Instance-backed state persistence is locally
proven for intentionally hoisted components. Automatic identity-keyed host
storage for inline state is an accepted design but remains unimplemented; see
the open item in [`tasks/todo.md`](../tasks/todo.md).

Gama rebuilds view content into a retained render tree, but it does not yet
relocate every property-wrapper value into a host-owned identity store. The
distinction between view identity, component-instance lifetime, and host
lifetime is therefore part of the public programming model today.

## The three lifetimes

| Lifetime | Identity | Typical owner | Examples |
| --- | --- | --- | --- |
| Application | The `App` value | shell or runtime | shared models, hoisted components, services |
| Surface host | `SceneID` + `WindowInstanceID` | backend or `GamaAppleShell` | focus, actions, subscriptions, dirty state |
| Render node | structural `NodeID` for one frame path | `BuildContext` | focus reconciliation, hit testing, `ForEach` children |

A component instance may be application-owned, surface-owned by application
code, or ephemeral inside a scene closure. `@State` and `@Reactive` currently
follow that instance.

## Persistent state: hoist intentionally

This shape creates a fresh `CounterPanel` whenever the scene content is
evaluated:

```swift
struct CounterApp: App {
    init() {}

    var scenes: some Scene {
        Window("Counter", id: "main", role: .primary) {
            CounterPanel() // New instance on a later rebuild.
        }
    }
}
```

Use a stable owner for instance-backed state:

```swift
struct CounterApp: App {
    private let panel = CounterPanel()

    init() {}

    var scenes: some Scene {
        Window("Counter", id: "main", role: .primary) {
            panel
        }
    }
}
```

The repository demo uses this exact pattern. It is an ownership decision, not
a performance trick.

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

`State<Value>` is the property-wrapper form. `@Reactive` is macro sugar that
generates a `GamaCore::Signal` peer and accessors. They use the same runtime;
neither wrapper creates a global observer or a SwiftUI dependency.

These types are not `Sendable`. They belong to an owning executor/host.
Transferring exclusive ownership is different from sharing; use an explicit
`sending` boundary when an API genuinely transfers a value.

## Invalidation from inside and outside a frame

An action registered during rendering runs through the owning `FrameHost`.
After invocation, the host marks itself dirty, so ordinary button/toggle/text
input does not require a separate observer.

External model changes need an explicit connection:

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
deleted, or reordered. Focus is stored as `NodeID`, not as an array index, so
stable identity lets focus survive unrelated collection changes.

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
to a collision-free `NodeID` instead of hashing a transient position.

Duplicate interactive identities are reported through
`FrameHost.duplicateIDs` after the frame is built. A backend may surface this
as a development diagnostic; malformed identity does not become a
process-global crash.

## Multiple windows

Every live surface owns an independent `FrameHost`, so focus, actions,
subscriptions, dirty state, and frame production are isolated by default.
Application-owned models can still be intentionally shared.

There are three common ownership shapes:

1. **Shared model:** the `App` owns one signal/model and multiple windows
   observe it. A change intentionally dirties every subscribed host.
2. **Shared component:** the `App` hoists one stateful component and uses it in
   multiple surfaces. Its instance-backed state is shared.
3. **Per-surface model:** application code creates one model/component for
   each payload or live instance and supplies it to that surface.

Gama does not currently synthesize case 3 from an inline `@State` declaration.
Do not describe a hoisted component inside a `WindowGroup` as per-window
storage.

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

- `Signal` explicitly declares `~Sendable`.
- Its unavailable `@unchecked Sendable` conformance produces a named
  diagnostic when code attempts to use it as ordinarily sendable.
- `FrameHost` and `AppRuntime` are `~Copyable` because a copy would share live
  reference state.
- `GamaCore` does not import `Synchronization` or a platform threading module.

If a platform model is actor-isolated, cross that boundary in application or
host-service code and deliver an ordinary value/action to the owning Gama
host. Do not make the renderer itself an authority over the actor or service.

## Current limitation and accepted direction

The accepted view-state design proposes a host-owned store keyed by structural
identity plus a diagnostic for transient inline state. Until that work lands
with its Embedded and host-less rendering proofs, the hoisting rule above is
the current behavior.

The design record is
[2026-08-29-view-state-identity-design.md](superpowers/specs/2026-08-29-view-state-identity-design.md).
Its accepted status does not make its proposed types or guarantees available
in current source.

## Tests to use

Use source identifiers, not `@Suite` display names:

```bash
unset TOOLCHAINS
swiftly run swift test \
  --scratch-path /private/tmp/gama-state-tests \
  --filter ReactiveStateLifetimeTests
```

Then run `check-boundaries.sh`, `check-concurrency-negative.sh`, and the full
Apple gate before changing confinement or lifetime semantics. A wrong filter
can exit zero after running no tests, so confirm the final test count.
