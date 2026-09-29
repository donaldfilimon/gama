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

Capability status for the AppKit host lives in `docs/Capabilities.md` and
is currently Unverified (the `AppleHostTests` suite identifier changed
after anchor `0f498d5`). This catalog does not restate hosted or local
proof. iOS/tvOS/visionOS compile status is in that ledger.

VoiceOver reads the frame the host already rendered.
``GamaHostView/accessibilitySnapshot`` derives reading-order text from
``GamaHostView/currentDrawList`` through `GamaDraw`'s
`AccessibilitySnapshot`, and the host publishes itself as a container whose
children are one ``GamaAccessibilityLineElement`` per non-blank grid row.
The adapter exposes text only: it adds no actions and no parallel account of
what the application means. The VoiceOver / assistive-text row in
`docs/Capabilities.md` is Locally proven on AppKit; UIKit compile status
and the absence of a screen-reader pass are in that ledger.

``GamaNativeHostView`` is the second host (ADR 0017), macOS only: it
presents the same surface with real AppKit controls (`NSTextField` labels
and fields, `NSButton` push buttons and checkboxes, `NSProgressIndicator`,
`NSBox` separators) at frames `LayoutEngine` computes in points with
``AppKitLayoutMetrics``, and routes activation, text edits, and focus back
to `FrameHost`. It paints no cells and publishes no `DrawList`; the native
controls are the accessibility elements. No capability row covers it yet.

This module embeds a view; it does not own the application. Applications
that want Gama to own `NSApplication`, windows, and lifecycle use the
separate `GamaAppleShell` product. The embedding guide is
`docs/backends/AppleUI.md`.

## Topics

### Hosting

- ``GamaHostView``
- ``GamaPlatformView``

### Native presentation

- ``GamaNativeHostView``
- ``AppKitLayoutMetrics``

### Assistive technology

- ``GamaAccessibilityLineElement``
