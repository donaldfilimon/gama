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

## `App`, `View`, and `Scene` are no longer `Sendable` (2026-08-27)

`Signal` is now non-`Sendable`, so every type that transitively owns one
drops the `Sendable` claim it could only satisfy because `Signal` laundered
its own. If you wrote `struct MyApp: App, Sendable` or passed a view across
an isolation boundary, that no longer type-checks — which is the point: it
never was safe, it was merely unchecked.

Host services (log, clock, filesystem), the window command channel, and
scene payload values remain `Sendable`; those genuinely cross contexts.

See [ADR 0009](adr/0009-signal-is-not-sendable.md), which also records a
measured correction: a retroactive `@unchecked Sendable` conformance still
compiles with a warning, so the confinement is loudly enforced, not
impossible to defeat.
