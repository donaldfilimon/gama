# ``GamaSwiftUI``

Show a Gama surface inside a SwiftUI view hierarchy.

## Overview

GamaSwiftUI bridges one Gama application's primary scene into SwiftUI.
``GamaView`` validates the app's scene graph when it is created, throwing a
typed `SceneConfigurationError` for an invalid app, and then wraps
`GamaAppleUI`'s `GamaHostView` through `NSViewRepresentable` on macOS or
`UIViewRepresentable` on iOS, iPadOS, tvOS, and visionOS. The host view keeps
owning the frame pump, event routing, resizing, and painting.

Every time SwiftUI materializes the view it gets an independent host: its own
frame host, focus and action state, `@Reactive` state, subscriptions, and
draw list. A `Signal` stored on the app is shared only between
materializations of the same ``GamaView`` value; separate initializer calls
create separate app instances. Parent body updates never reinstall the app,
and a replacement ``GamaView`` value is ignored once the view is
materialized, so create the value once and hold it rather than building it
in a frequently re-evaluated `body`. Removing the view cancels the host's
subscriptions. Only the primary scene renders; auxiliary scenes, window
commands, and lifecycle events belong to `GamaAppleShell`.

Where SwiftUI or a platform view toolkit is unavailable, the module is empty.
The usage walkthrough and verification boundary live in
`docs/backends/SwiftUI.md`; this catalog makes no capability claim.

## Topics

### Embedding

- ``GamaView``
