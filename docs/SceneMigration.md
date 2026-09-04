# Migrating to scene-first applications

The pre-release `App.content` API has been replaced by an explicit scene graph.
This is an intentional source break: Gama has no published tags or releases,
and every in-repository consumer migrates in the same change.

Before:

```swift
struct ExampleApp: App {
    var content: some View { ExampleView() }
}
```

After:

```swift
struct ExampleApp: App {
    var scenes: some Scene {
        Window("Example", id: "main", role: .primary) {
            ExampleView()
        }
    }
}
```

Every app must declare exactly one primary scene. Single-surface backends render
that primary explicitly, so putting it first is neither required nor meaningful.

Use a typed group when a logical payload identifies each window:

```swift
struct DocumentID: Hashable, Sendable {
    let value: Int
}

let documents = WindowGroupKey<DocumentID>("documents")

struct DocumentsApp: App {
    var scenes: some Scene {
        WindowGroup(
            "Document",
            key: documents,
            role: .primary,
            initialValue: DocumentID(value: 1)
        ) { document in
            DocumentView(document: document)
        }

        Window("Inspector", id: "inspector") {
            InspectorView()
        }
    }
}
```

`WindowGroupKey<DocumentID>` accepts only `DocumentID`; passing a different
payload type does not compile. A primary or open-at-launch group needs an
initial value so TUI, WASM, Embed, and Dock reactivation can instantiate it.

`FrameHost` is now non-generic and no longer exposes `app`. Create shared state
before the host and place it in reference-backed models:

```swift
let model = Signal(0)
let app = ExampleApp(model: model)
var host = try FrameHost(app: app)
```

Swift host initialization now throws `SceneConfigurationError`. C/JNI/WASM
entry points translate invalid configuration into their ABI failure value.
Window actions are optional capabilities: outside `GamaAppleShell`, opening or
dismissing a window returns `false` and the current surface continues rendering.

## Resize timing is now eager on every backend (2026-08-27)

Before wave 2, a `.resize` reached handling code immediately on Embed and
WASM but only at the *next* pump on TUI and AppleUI. All four backends now
share one canonical `HostPump` whose policy is eager: `.resize` updates the
pump's size and invalidates the host **before** the event is forwarded.

If you wrote code that relied on reading the old extent during a resize on
TUI or AppleUI, it now sees the new one:

`.resize` is handled by `FrameHost` and never reaches
`App.handleLifecycle` — `LifecycleEvent` carries no resize case and no
extent. The extent a backend lays out against is the pump's:

```swift
// Before (TUI/AppleUI): the pump still reported the pre-resize extent
//                       while the event was being forwarded.
// After (everywhere):   `pump.size` is already the new extent, and the
//                       host has already been invalidated.
pump.handle(.resize(renderer.size))
_ = pump.size  // the new extent, before any view code runs
```

Embed and WASM are unaffected — they already behaved this way. See
[ADR 0008](adr/0008-one-pump-eager-resize.md).

## Host-confined declarations are no longer `Sendable` (2026-08-27)

`Signal` is now non-`Sendable`, so every type that transitively owns one
drops the `Sendable` claim it could only satisfy because `Signal` laundered
its own. If you wrote `struct MyApp: App, Sendable` or passed a view across
an isolation boundary, that no longer type-checks — which is the point: it
never was safe, it was merely unchecked.

Host services (log, clock, filesystem), the window command channel, and
scene payload values remain `Sendable`; those genuinely cross contexts.

`PluginRuntime` follows the same rule and `PluginRuntime.install` now takes a
`sending` plugin. App ownership transfer is explicit at the long-lived Apple,
WASM, and C-embed install boundaries; the synchronous `AppRuntime`,
`FrameHost`, and scene compiler remain same-executor plumbing.

See [ADR 0009](adr/0009-signal-is-not-sendable.md), which also records a
measured correction: a retroactive `@unchecked Sendable` conformance still
compiles with a warning, so the confinement is loudly enforced, not
impossible to defeat.

## `@Reactive` state is per-surface (2026-09-04)

`@Reactive var x: T` now expands to a `ReactiveSlot<T>` peer instead of a
`Signal<T>`, and `@Component` synthesizes `render(in:)` to bind every slot to
the `FrameHost` that owns the build, keyed by the node's structural identity.
A component built inline in a scene closure is still a fresh value every
frame, but its state now lives in the host and survives the rebuild. The
hoisting workaround is no longer required:

```swift
// Before: hoisted so the instance — and the Signal it stored — outlived
//         the per-frame closure.
struct CounterApp: App {
    private let panel = CounterPanel()
    var scenes: some Scene {
        Window("Counter", id: "main", role: .primary) { panel }
    }
}

// After: inline is correct; state is host-owned per surface.
struct CounterApp: App {
    var scenes: some Scene {
        Window("Counter", id: "main", role: .primary) { CounterPanel() }
    }
}
```

Hoisting still compiles and still works, with one semantic flip: a hoisted
`@Reactive` component behind a `WindowGroup` used to share one instance's
state across every window; it is now per-window, and the instance's
pre-render value only seeds each surface's initial value. If you relied on
that sharing, move the value to a `Signal` the `App` owns and observe it.
The rule: `@Reactive` is per-surface; a `Signal` on the `App` is shared.

Two new compile errors replace silent local state:

- `@Reactive` outside a struct marked `@Component` (including in a class):
  `@Reactive requires a struct marked @Component; elsewhere its state never
  binds to a host`.
- A hand-written `render(in:)` in a `@Component` that has `@Reactive`
  properties: `@Component synthesizes render(in:) to bind @Reactive state;
  remove this render(in:) or the @Reactive properties`.

Raw `Signal` stored properties inside a component are unsupported; convert
them to `@Reactive` (the demo converted its `name` and `notifications`
signals this way). The generated `_name` peer is a `ReactiveSlot`, not a
`Signal`: `_name.binding()` keeps working for `TextField`/`Toggle`, and any
place that passed `_name` as a `Signal` becomes `_name.signal`. Bound
`@Reactive` state also invalidates the host on out-of-band writes without an
`observe()` call; raw signals still need one.

Structural keying means a branch flip or positional `ForEach` reorder drops
state. `IdentifiedForEach` and the new `.stateScope(_:)` modifier pin a
subtree to a chosen identity, and `FrameHost.transientStateIDs` reports the
nodes whose state was reconstructed. Host-less rendering, including
`gama-demo --emit-mlir`, keeps instance-local storage and emits identical
output.

See [ADR 0011](adr/0011-reactive-state-is-per-surface.md).
