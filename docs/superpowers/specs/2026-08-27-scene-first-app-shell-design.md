# Gama scene-first application and macOS shell design

Date: 2026-08-27. Status: **approved for implementation**.

This specification supersedes the 2026-08-26 app-shell draft. The earlier
draft proposed a single-window shell and explicitly deferred scenes; the
approved direction is scene-first and macOS multi-window. The retained render
IR, layout, drawing, and backend contracts remain the foundation.

## Scope and boundaries

This milestone has two delivery slices after the integration repair:

1. Scene core and atomic migration of every in-repository `App`.
2. A macOS AppKit shell and multi-window demonstration executable.

Packaging is the next roadmap item after these slices. Windows GUI, UIKit
scene delegates, web multi-window behavior, dynamic or out-of-process plugins,
distribution/notarization, persistent restoration, placement persistence, and
close vetoes are deliberately outside this design.

`GamaAppleUI` remains an embeddable host view. `GamaAppleShell` owns an entire
macOS application only when an application explicitly launches through it.

## Public application model

`App.content` is removed before 1.0. An app declares scenes and a lifecycle
handler instead:

```swift
public protocol App: Sendable {
    associatedtype Scenes: Scene
    @SceneBuilder var scenes: Scenes { get }
    init()
    func handleLifecycle(_ event: LifecycleEvent)
}
```

The lifecycle method has a no-op default. The shell constructs the app once.
Scene content closures therefore capture the same reference-backed model, while
every live surface receives an independent `FrameHost`.

The public scene vocabulary is stdlib-only and Embedded-Swift-safe:

- `Scene`, `SceneBuilder`, `SceneID`, and `WindowInstanceID`;
- `WindowGroupKey<Value>` constrained to `Hashable & Sendable`;
- `SceneRole.primary` and `.auxiliary`;
- `SceneLaunchBehavior.openAtLaunch` and `.onDemand`;
- `WindowConfiguration`, `Window`, and `WindowGroup`;
- `SceneConfigurationError` for validation and fail-closed type mismatches.

Exactly one scene is primary. IDs are unique across singleton windows and
groups. A primary scene defaults to open at launch; an auxiliary scene defaults
to on demand; either default may be overridden. A primary or open-at-launch
group must provide an initial payload.

Non-window backends compile the graph and render the explicit primary scene.
Declaration order is retained for launch and menu presentation but never
selects the primary implicitly.

## Identity and window commands

A singleton `Window` has at most one live instance. Opening it again focuses
that instance. A `WindowGroup` is keyed by `(WindowGroupKey, payload)`; opening
the same pair focuses the existing instance, while a distinct payload creates
a new shell-generated `WindowInstanceID`.

`WindowActions` is the fixed-key capability in `EnvironmentValues`:

- open or focus a singleton by `SceneID`;
- open or focus a typed group payload;
- dismiss the current or an explicitly identified instance.

Each operation returns whether the backend accepted it. `WindowContextReader`
lets ordinary view code capture the current identity and actions in callbacks.
TUI, WASM, Embed, Android, MLIR, and custom single-surface hosts install
unavailable actions, which return `false` rather than disrupting rendering.

An Apple shell owns an executor-confined command queue. View callbacks enqueue
commands; the shell drains them after event dispatch. Gama introduces no
process-global window registry.

## Compilation and host ownership

Scene compilation and payload erasure are package-private. Erasure accepts only
`Hashable & Sendable` values, retains immutable values, records concrete type
identity, and returns `SceneConfigurationError.internalTypeMismatch` instead of
trapping when a shell presents an incompatible payload.

`FrameHost` is non-generic and closure-backed. It owns only one surface's:

- focus identity and focusable geometry;
- action and key-handler tables;
- `SubscriptionContext` and dirty signal;
- lifecycle address and window context;
- frame production state.

It does not publicly retain an `App`. Shared application state belongs in
reference-backed models such as `Signal`. Draw buffers remain backend/session
owned, so distinct windows never share a buffer.

Failure boundaries remain typed:

- graph compilation and host initialization throw `SceneConfigurationError`;
- after successful initialization, `AppRuntime.run()` throws only the
  renderer's declared failure;
- `App.main(renderer:)` wraps those domains in `AppLaunchError`;
- Swift host APIs throw during initialization;
- C, JNI, and WASM ABI boundaries return null, a negative code, or remain inert
  on impossible configuration errors and never trap across the ABI.

## Lifecycle contract

`InputEvent.lifecycle(LifecycleEvent)` is the portable event channel.
Application events are `didLaunch`, `willEnterForeground`,
`didEnterBackground`, and `willTerminate`. Window events carry both `SceneID`
and `WindowInstanceID`: `windowDidOpen`, `windowCloseRequested`,
`windowDidClose`, `windowDidBecomeKey`, and `windowDidResignKey`.

The shared app handler receives application events once per application, not
once per window. Addressed events dirty only their matching host unless a
shared model mutation independently invalidates other observing hosts.

TUI Ctrl-C and Ctrl-Q retain their hardwired exit behavior and first synthesize
an addressed `windowCloseRequested` for the primary surface. This makes every
quit path observable without adding close cancellation.

## macOS shell

`GamaAppleShell` depends on `GamaCore`, `GamaDraw`, and `GamaAppleUI`.
`@MainActor GamaShell.run(AppType.self)` validates the graph before entering
AppKit, then:

1. creates `NSApplication` with regular activation policy;
2. installs a minimal application menu containing Quit;
3. owns the application and window delegates;
4. opens every scene configured `openAtLaunch`;
5. creates one `NSWindow`, `GamaHostView`, frame host, draw buffer, and context
   per live instance;
6. translates AppKit activation, focus, close, and termination callbacks into
   portable lifecycle events;
7. drains queued window commands after dispatch.

Close requests are not vetoable in this version. The shell emits
`windowCloseRequested`, cancels only that host's subscriptions, closes the
native window, and emits `windowDidClose`. Closing the last window does not
terminate the process; `applicationShouldTerminateAfterLastWindowClosed`
returns `false`. Dock activation with no live windows opens or focuses the
primary scene using its initial payload. Only explicit Quit or Command-Q emits
`willTerminate` and exits.

The `gama-apple-demo` executable uses a typed primary group and an auxiliary
singleton. It demonstrates idempotent focus for the same payload, independent
hosts for distinct payloads, close-all residency, Dock reopening, and explicit
quit.

## Acceptance

Portable tests cover builder order, validation errors, launch defaults, typed
payloads, primary-only rendering, unavailable actions, shared-model
invalidation, per-host cancellation, host-local isolation, and TUI lifecycle
ordering. AppKit tests create controllers and invoke delegate methods without
entering the global event loop. A supplemental manual smoke exercises the real
Dock and Command-Q paths.

Every slice must pass focused Swift Testing, Apple build/test/release,
boundaries, docs, Embedded, WASM, Linux, Android/emulator, C ABI, MLIR, and
Windows console gates wherever locally available, followed by the complete
hosted matrix. A pull request is not merged until all six hosted jobs are green.

Capabilities documentation distinguishes implementation, local proof, hosted
proof, provisional behavior, and blocked/deferred platforms. It must not imply
that Windows GUI, UIKit scene glue, restoration, close vetoes, packaging, or
plugin loading shipped with this milestone.
