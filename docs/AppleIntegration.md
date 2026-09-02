# Apple application integration

Status: Direct AppKit hosting and the macOS shell are implemented and locally
runtime proven; AppKit is hosted proven. UIKit branches are compile proven for
iOS, tvOS, and visionOS only. Gama currently ships no SwiftUI, SwiftData, or
Foundation Models product target.

This guide explains where Gama ends and an Apple application begins. The
portable renderer owns application scene, layout, focus, action, and draw-list
semantics. Apple layers own native windows/views, platform events, persistence,
model sessions, system presentation, and credentialed distribution.

## Choose the owning layer

| Requirement | Owning layer |
| --- | --- |
| Portable layout, interaction, scene semantics | `GamaCore` |
| CoreGraphics presentation in an existing native view | `GamaAppleUI` |
| A complete macOS AppKit application and multi-window policy | `GamaAppleShell` |
| Foundation-backed clock/files/environment/logging | `GamaPlatformServices` behind interfaces |
| SwiftUI navigation, commands, toolbar, settings, or Liquid Glass | application presentation layer |
| SwiftData schema, model container, migrations, persistence | application data layer |
| Foundation Models session, tools, prompts, generation | application/service layer |
| Signing, entitlements, notarization | packaging and release workflow |

Do not add an Apple framework to `GamaCore` to solve an application-layer
need. The boundary gate rejects Foundation, AppKit, UIKit, SwiftUI,
Observation, Synchronization, POSIX, and WinSDK imports there.

## Embedding in AppKit

`GamaHostView` owns a `FrameHost`, translates AppKit events, schedules dirty
frames, and draws the shared `DrawList` through CoreGraphics.

The minimal shape is in `Examples/AppleHost/main.swift`:

```swift
import AppKit
import GamaAppleUI
import GamaCore

struct AppleExample: App {
    init() {}

    var scenes: some Scene {
        Window("Gama Apple", id: "main", role: .primary) {
            VStack {
                Text("Gama Apple").bold()
                Button("Action") {}
            }
        }
    }
}

let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 640, height: 360),
    styleMask: [.titled, .closable, .resizable],
    backing: .buffered,
    defer: false
)
window.contentView = try GamaHostView(app: AppleExample())
window.makeKeyAndOrderFront(nil)
```

This snippet demonstrates view integration, not the `NSApplication` run loop
or distribution. Use `gama-apple-demo` for a complete shell and the packaging
workflow for an `.app`.

## Using the macOS shell

`GamaAppleShell` compiles the full scene graph and owns native window
instances. It supports:

- One explicit portable primary scene.
- Auxiliary singleton `Window` declarations.
- Typed, payload-addressed `WindowGroup` declarations.
- Reopen/focus of an existing singleton or payload instance.
- One independent `FrameHost` per live surface.
- Lifecycle delivery addressed by scene and instance identity.

Run it through the maintained driver:

```bash
.agents/skills/run-gama/driver.sh apple
```

Use [backends/AppleShell.md](backends/AppleShell.md) for the exact lifecycle
contract and manual-smoke checklist.

## UIKit scope

`GamaAppleUI` has UIKit compilation branches for iOS, tvOS, and visionOS. The
acceptance matrix builds those destinations with Xcode's default Swift 6.4
toolchain because the package manifest intentionally stays at tools version
6.4.

That proves source and SDK compatibility. It does not prove installation,
touch/focus behavior, accessibility, application lifecycle, simulator launch,
or physical devices. Those remain separate runtime acceptance layers.

## SwiftUI composition

There is no current `GamaSwiftUI` product. A SwiftUI application may still
host an AppKit/UIKit-backed surface using its own representable/coordinator
layer, but that bridge is application code until a separately designed and
tested framework product lands.

The intended ownership shape is:

```text
SwiftUI scene/navigation/commands/native chrome
  -> stable coordinator owns one Gama host per SwiftUI identity
  -> Gama surface renders retained content
  -> ordinary values/actions cross the boundary
```

Important constraints:

- SwiftUI body updates must not reinstall the Gama application or reset its
  host.
- Keep Gama's surface in a stable content plane; native controls are outer
  presentation, not replacement renderer semantics.
- `Task {}` inherits actor context. Move CPU-heavy work through an explicit
  non-main boundary, then deliver state back to the appropriate owner.
- Use stable domain identity for mutable collections in both layers.
- Liquid Glass belongs to native control chrome with availability and fallback
  behavior; it does not enter `GamaCore` or the draw-list wire format.

Do not copy proposed `GamaSwiftUI` APIs out of a dated roadmap and describe
them as available source. Plans are not products.

## SwiftData

SwiftData belongs to the application persistence layer. Gama has no
framework-owned schema or persistence model.

A sound flow is:

```text
SwiftData model/container
  -> application maps persisted data to a Sendable domain value
  -> owning Gama model/signal updates on its executor
  -> FrameHost observation or invalidation requests a frame
```

Keep these concerns separate:

- SwiftData context ownership and save/migration failures stay in the app.
- Gama scene/view types do not become persistence entities.
- Portable renderer state does not depend on an Apple-only store.
- Loading or saving does not occur inside a per-frame view-content closure.
- A persisted identifier may become domain identity, but storage row order is
  not a substitute for stable UI identity.

Tests for the app's SwiftData layer do not replace Gama frame/layout tests, and
Gama's cross-platform matrix does not prove the app's migrations.

## Foundation Models

Foundation Models is an application or host-service concern. Model output is
advisory data, not authority over rendering, input delivery, lifecycle,
window disposition, or safety-sensitive actions.

A safe boundary is:

```text
Foundation Models session and tools
  -> application validates/cancels/maps output
  -> typed domain value or explicit user-confirmed action
  -> Gama model
  -> observed/invalidation-driven frame
```

Requirements for any real integration:

- Keep session and tool objects out of stdlib-only targets.
- Respect availability and device capability in the app.
- Isolate model work from the main actor when the API contract permits it.
- Validate structured output before it reaches application state.
- Require explicit confirmation for destructive or externally visible actions.
- Model cancellation, failure, partial output, and unsupported-device states.
- Test the application's fallback path independently of Gama.

The framework's current source contains no model-session authority. That is
the correct cross-platform default.

## Accessibility and native behavior

The AppKit adapter has automated coverage for derived accessibility text and
bridge behavior. Real VoiceOver and UIKit screen-reader interaction remain
manual evidence. A semantic control must retain its role, name, value/state,
actions, focus/keyboard operation, and alternatives to gesture, hover, and
color.

Likewise, offscreen shell tests do not prove Dock reopen, visible window focus,
close behavior, or Command-Q in a human session. Keep those manual checks
separate in reports.

## Verification

Focused AppKit host and shell checks:

```bash
unset TOOLCHAINS
swiftly run swift test \
  --scratch-path /private/tmp/gama-apple-integration \
  --filter AppleHostFontCacheTests
swiftly run swift test \
  --scratch-path /private/tmp/gama-apple-integration \
  --filter AppleShellTests
```

Full Apple and platform compilation:

```bash
./scripts/check-apple.sh
./scripts/check-apple-platforms.sh
```

See [Verification.md](Verification.md) before upgrading compile proof into a
runtime, accessibility, packaging, signing, or hosted claim.
