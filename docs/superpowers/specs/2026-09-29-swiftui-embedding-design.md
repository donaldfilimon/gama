# SwiftUI embedding: `GamaView`

**Status: built on a feature branch, awaiting owner review (2026-09-29); no
evidence-ledger row.** Track 4 of the
[native UI roadmap](2026-09-29-native-ui-roadmap-design.md), first half. The
SwiftData half is a separate draft:
[SwiftData-backed reactive persistence](drafts/2026-09-29-swiftdata-reactive-persistence-draft.md).
Plan: [SwiftUI embedding plan](../plans/2026-09-29-swiftui-embedding.md).

## Goal

A SwiftUI application shows a Gama surface by writing one view:

```swift
import GamaCore
import GamaSwiftUI
import SwiftUI

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

The value is created once and held: each initializer call compiles the scene
graph, and `GamaView(_:)` also runs the app's no-argument initializer, so
building it inside a frequently re-evaluated `body` repeats both (see open
question 2).

Before this, `docs/AppleIntegration.md` told applications to write their own
representable around `GamaHostView`. Every application would have repeated the
same three decisions (when to validate, when to install, when to tear down),
and each could get them subtly wrong.

## Non-goals

- **Native presentation.** `GamaView` wraps `GamaHostView`, the cell-painting
  host. Once track 3's `GamaNativeHostView` exists, a second initializer or a
  presentation option selects it. That is a follow-up, not part of this spec.
- **Auxiliary scenes and window commands.** Only the primary scene renders, as
  on every backend except `GamaAppleShell`. SwiftUI owns windows here; a Gama
  `openWindow` action has nowhere to go and stays unavailable.
- **Gama lifecycle events.** SwiftUI's `scenePhase` is not translated into
  `LifecycleEvent`. See the open questions.
- **Gama hosting SwiftUI views.** Deferred by the roadmap to track 3's mapping.
- **SwiftData.** Separate draft, not built.

## Decisions

### 1. A new Apple-only target, `GamaSwiftUI`

The type lives in its own library target, depending on `GamaCore` and
`GamaAppleUI` only. It never enters a portable target, and it is added to the
`GamaPlatformServices` inverse ban in `scripts/check-boundaries.sh` like every
other framework target. The whole source file sits under
`#if canImport(SwiftUI) && (canImport(AppKit) || canImport(UIKit))`, so on
Linux, Android, and wasm32 the target compiles to an empty module, the same
shape as `GamaAppleShell` without AppKit. It uses `strictLibrary` like every
shipped library (ADR 0012), which `scripts/package-graph.py` enforces by
derivation, so no list there changes.

### 2. Validate in `init`, install in `make`, tear down in `dismantle`

- `GamaView.init(app:)` compiles the scene graph and builds the primary
  `SceneSurface`, throwing `SceneConfigurationError`. This mirrors
  `GamaShell.run`, which finishes scene validation before AppKit starts: a
  misconfigured app fails where the caller can handle it, never as a blank
  view.
- `makeNSView`/`makeUIView` create a `GamaHostView` and call its package
  `install(surface:)`. The frame pump, event routing, resize handling, and
  painting are the host's; `GamaSwiftUI` adds none of its own.
- `updateNSView`/`updateUIView` do nothing. SwiftUI calls them whenever the
  parent's body re-evaluates, and reinstalling there would reset the surface
  (`docs/AppleIntegration.md` names that as the constraint to keep).
- `dismantleNSView`/`dismantleUIView` call the host's package `tearDown()`,
  which cancels subscriptions and detaches the pump. `GamaShell` does the same
  when a window closes.

Each materialization creates its own host, so two `GamaView`s built from one
value, or one view shown twice, get independent frame hosts, `@Reactive`
state, and draw lists. That is ADR 0011's per-surface rule applied to SwiftUI
identity. A `Signal` stored on the app value is shared between them, exactly
as between two windows of one `WindowGroup`; that sharing needs one value,
because separate `GamaView(_:)` calls create separate app instances. After the
first materialization a replacement `GamaView` value from the parent is
ignored, since the update hook does nothing.

### 3. A minimal public surface

The public API is `GamaView`, its two initializers, and `body`. The
representable is a `package` type, so its witnesses are not public API and the
tests can call the factory (`makeHostView()`) and teardown
(`dismantleHostView(_:)`) directly, since a representable context cannot be
constructed in a test.

### 4. Name qualification

A file that imports both SwiftUI and GamaCore sees two `App`, `View`, `Scene`,
`Text`, and `Window` types. `GamaSwiftUI` qualifies every use
(`GamaCore.App`, `SwiftUI.View`), and the backend guide tells applications to
do the same in files that import both.

## Testing

`Tests/gamaTests/SwiftUIEmbeddingTests.swift`, AppKit only:

- an app without a primary scene throws `noPrimaryScene` from both
  initializers;
- the factory installs the primary surface and the draw list contains the
  primary scene's text and none of the auxiliary scene's;
- two materializations of one value keep independent `@Reactive` state and
  draw lists: activating the counter in one host leaves the other at zero;
- dismantling tears the session down: a model change followed by
  `invalidate()` no longer reaches the draw list (checked by mutation: with
  teardown removed, this test fails);
- an `NSHostingView` in an offscreen window materializes a live
  `GamaHostView` through the representable; replacing the hosting view's root
  makes SwiftUI dismantle it, after which a model change no longer reaches the
  host's draw list.

The `GamaSwiftUI` scheme is registered in `scripts/check-apple-platforms.sh`
for the iOS, tvOS, and visionOS simulators alongside `GamaAppleUI`, but that
gate was not run on this branch (it hardcodes shared derived-data paths), so
the UIKit branch has no compile evidence until integration runs it. No
simulator runtime test exists for either.

## Open questions for the owner

1. **Lifecycle.** Should `GamaView` translate SwiftUI `scenePhase` into
   `willEnterForeground`/`didEnterBackground`, and appearance into
   `windowDidOpen`/`windowDidClose` for its one instance? Today it delivers
   none, so an app that relies on those events behaves differently embedded
   than under `GamaShell`.
2. **Recreated values.** SwiftUI recreates `GamaView` values whenever a parent
   body re-evaluates, and `init` compiles the scene graph each time. Scene
   compilation does not run content closures, so it is cheap, but a caller
   that builds the app value inside a frequently re-evaluated body pays it
   repeatedly. Is that acceptable, or should the view take a stable
   application object?
3. **External invalidation.** A SwiftUI state change that should re-render
   the Gama surface has no path other than a shared `Signal` or a bound
   `@Reactive` write. Should `GamaView` expose an explicit invalidation hook?
4. **Native presentation switch.** When `GamaNativeHostView` lands, is the
   choice an initializer parameter, a SwiftUI environment value, or a
   separate view type?
