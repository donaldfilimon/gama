# ``GamaAppleUI``

Host a Gama surface inside any AppKit or UIKit view hierarchy.

## Overview

GamaAppleUI is the embeddable native Apple backend: ``GamaHostView`` is a
`@MainActor` `NSView`/`UIView` subclass (the platform split is the
``GamaPlatformView`` typealias) that pumps one app's `FrameHost`, paints the
shared `DrawList` through CoreGraphics as a monospaced character grid, and
translates keyboard, mouse, scroll, and touch input into `InputEvent`
values. Like every backend it only carries events in and frames out;
interaction semantics stay in GamaCore. The whole target is `@MainActor`,
so AppKit/UIKit isolation is enforced by the compiler rather than
convention.

``GamaHostView/install(app:)`` validates the app's scene graph and renders
its explicit primary scene; installing again replaces the session wholesale
and cancels the previous session's model subscriptions first. Out-of-band
state changes request a frame through the non-mutating
``GamaHostView/invalidate()``, and the most recent frame is exposed
read-only as ``GamaHostView/currentDrawList`` for accessibility adapters
and diagnostics.

Per the evidence ledger (`docs/Capabilities.md`), the AppKit host is
locally runtime proven by the Swift Testing AppKit suite (instantiation,
layout, invalidation, draw-list production); the iOS/tvOS/visionOS UIKit
host is compile proven only: simulator builds, no hosted runtime
execution. VoiceOver accessibility from the draw list is a ledgered
Provisional item, not a shipped claim.

This module embeds a view; it does not own the application. Applications
that want Gama to own `NSApplication`, windows, and lifecycle use the
separate `GamaAppleShell` product. The embedding guide is
`docs/backends/AppleUI.md`.

## Topics

### Hosting

- ``GamaHostView``
- ``GamaPlatformView``
