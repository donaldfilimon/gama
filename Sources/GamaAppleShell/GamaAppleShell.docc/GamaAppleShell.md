# ``GamaAppleShell``

Let Gama own a complete macOS application: windows, lifecycle, and
termination.

## Overview

GamaAppleShell is the opt-in AppKit application owner for scene-first Gama
applications. ``GamaShell/run(_:)`` compiles and validates the app's scene
graph *before* `NSApplication` starts (a configuration error surfaces as a
typed `SceneConfigurationError` throw, never as a half-launched process),
then configures the shared application, installs a minimal main menu, and
enters the AppKit event loop.

The shell opens every `openAtLaunch` declaration in source order. Reopening
a singleton window or an already-open typed group payload focuses the
existing window; a new payload creates an independent controller, frame
host, focus/action state, subscriptions, dirty state, and draw list. There
is no process-global scene or window registry: window actions drain from a
per-shell, main-actor-confined store after Gama event dispatch, and AppKit
activation, focus, close, and termination callbacks become portable
`LifecycleEvent` values addressed to the live host they concern.

Close is deliberately non-vetoable in this version, closing the final
window leaves the application resident, a Dock reopen recreates the primary
scene from its initial payload, and only explicit Quit terminates. Per the
evidence ledger (`docs/Capabilities.md`), the shell is implemented and
locally proven by the pinned Apple build plus offscreen AppKit tests that
never enter the global event loop; the Dock/Command-Q smoke remains
supplemental and manual, and packaging, placement restoration, close veto,
UIKit scene delegates, and a Windows GUI are not shipped.

Embedding a Gama surface in an application you own is the separate
`GamaAppleUI` product; the launch walkthrough, lifecycle detail, and manual
smoke checklist live in `docs/backends/AppleShell.md`.

## Topics

### Application ownership

- ``GamaShell``
