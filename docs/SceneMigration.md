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
