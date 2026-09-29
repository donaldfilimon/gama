# SwiftUI embedding (GamaSwiftUI)

Status: Unverified. There is no `docs/Capabilities.md` row for this product
yet; this guide makes no implemented, locally proven, or hosted claim. Design:
[SwiftUI embedding](../superpowers/specs/2026-09-29-swiftui-embedding-design.md).

`GamaSwiftUI` lets a SwiftUI application show the primary scene of a Gama
`App`. `GamaView` wraps `GamaAppleUI`'s `GamaHostView` through
`NSViewRepresentable` on macOS and `UIViewRepresentable` on iOS, iPadOS, tvOS,
and visionOS. It adds no renderer of its own: frames, events, resizing, and
painting are the host view's.

## Use

```swift
import GamaCore
import GamaSwiftUI
import SwiftUI

struct CounterApp: GamaCore.App {
    var scenes: some GamaCore.Scene {
        GamaCore.Window("Counter", id: "main", role: .primary) {
            GamaCore.Text("Hello from Gama")
        }
    }
}

struct ContentView: SwiftUI.View {
    var body: some SwiftUI.View {
        if let gama = try? GamaView(CounterApp.self) {
            gama.frame(minWidth: 320, minHeight: 180)
        }
    }
}
```

A file that imports both SwiftUI and GamaCore sees two `App`, `View`,
`Scene`, `Text`, and `Window` types; qualify them as above, or keep the Gama
app declaration in a file that does not import SwiftUI.

## Behavior

- **Validation first.** Both initializers compile the scene graph and throw
  `SceneConfigurationError` for an invalid app before SwiftUI lays anything
  out.
- **Primary scene only.** Auxiliary scenes and window commands need
  `GamaAppleShell`; an embedded surface ignores them.
- **One host per materialization.** Each time SwiftUI creates the underlying
  platform view, a new `GamaHostView` gets its own frame host, `@Reactive`
  state, subscriptions, and draw list. A `Signal` stored on the app is shared.
- **Parent updates do not reinstall.** SwiftUI body re-evaluation leaves the
  host alone. To re-render after a change the host cannot observe, write to a
  `Signal` or bound `@Reactive` state.
- **Removal tears down.** When SwiftUI removes the view, the host's
  subscriptions are cancelled and its frame pump detached.
- **No lifecycle events.** SwiftUI scene phases are not translated into Gama
  `LifecycleEvent`s (an open question in the design).
- **Inert elsewhere.** Without SwiftUI and a platform view toolkit the target
  compiles to an empty module.

## Verification

`SwiftUIEmbeddingTests` in `Tests/gamaTests/SwiftUIEmbeddingTests.swift` runs
under `scripts/check-apple.sh` on macOS, including an `NSHostingView` case in
an offscreen window. The UIKit branch is only compiled, by
`scripts/check-apple-platforms.sh`; nothing runs it on a simulator or device.
