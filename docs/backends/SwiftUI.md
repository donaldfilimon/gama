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

@main
struct HostApp: SwiftUI.App {
    // Created once for the process; body re-evaluation reuses it.
    private let gama = try? GamaView(CounterApp.self)

    var body: some SwiftUI.Scene {
        SwiftUI.WindowGroup {
            if let gama {
                gama.frame(minWidth: 320, minHeight: 180)
            } else {
                SwiftUI.Text("Invalid Gama app")
            }
        }
    }
}
```

Create a `GamaView` once and hold it, as above; do not build it inside a
`body` that SwiftUI re-evaluates. Each initializer call compiles the scene
graph, and `GamaView(_:)` runs the app's no-argument initializer every time,
so any side effect in that initializer repeats.

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
  state, subscriptions, and draw list. A `Signal` stored on the app is shared
  only between materializations of the same `GamaView` value (one value shown
  twice, or re-materialized). Separate `GamaView(_:)` calls create separate
  app instances, which share nothing.
- **Parent updates do not reinstall.** SwiftUI body re-evaluation leaves the
  host alone, and a replacement `GamaView` value passed by a parent after the
  first materialization is ignored. To re-render after a change the host cannot observe, write to a
  `Signal` or bound `@Reactive` state.
- **Removal tears down.** When SwiftUI removes the view, the host's
  subscriptions are cancelled and its frame pump detached.
- **No lifecycle events.** SwiftUI scene phases are not translated into Gama
  `LifecycleEvent`s (an open question in the design).
- **Inert elsewhere.** Without SwiftUI and a platform view toolkit the target
  compiles to an empty module.

## Verification

`SwiftUIEmbeddingTests` in `Tests/gamaTests/SwiftUIEmbeddingTests.swift` runs
under `scripts/check-apple.sh` on macOS. It covers validation, primary-only
rendering, independent `@Reactive` state and draw lists across two
materializations of one value, teardown through the package dismantle hook,
and an `NSHostingView` case in an offscreen window whose root is replaced, so
SwiftUI itself dismantles the host and a later model change no longer reaches
its draw list. Focus and subscription independence across hosts hold by
construction (each host installs its own session) and are not separately
tested.

The `GamaSwiftUI` scheme is registered in `scripts/check-apple-platforms.sh`
beside `GamaAppleUI`, but that gate was not run on the branch that added it,
so the UIKit branch has no compile evidence until it does. Nothing runs the
UIKit branch on a simulator or device.
