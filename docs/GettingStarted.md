# Getting started

Status: Current onboarding guide for the unreleased `main` branch. The terminal
workflow is locally runnable on macOS and Linux; platform proof and exceptions
remain authoritative in [Capabilities.md](Capabilities.md).

This guide gets from a clean checkout to a running Gama application, then
explains the two decisions that most often surprise new contributors: every
application declares one primary scene, and `@Reactive` component state is
stored per surface by the host, keyed by position, so it outlives the
scene-content closure that is evaluated for each frame.

## 1. Confirm the toolchain

Gama is not built with whichever `swift` happens to be first on `PATH`. The
repository pins a complete Swift 6.5 development snapshot in `.swift-version`
and records every compiler and SDK artifact in `Toolchains.toml`.

From the repository root:

```bash
unset TOOLCHAINS
swiftly run swift --version
```

The first line must report Apple Swift 6.5-dev. If it does not, stop and use
[Toolchain.md](Toolchain.md); a successful build under another compiler is not
equivalent evidence.

The checkout is FileProvider-managed. Keep build and test products outside the
repository:

```bash
unset TOOLCHAINS
swiftly run swift build --scratch-path /private/tmp/gama-getting-started
```

## 2. Run the maintained demos

The terminal demo is the fastest interactive route:

```bash
.agents/skills/run-gama/driver.sh smoke
```

The driver builds with the pin, launches `gama-demo` in a real 100x30 TTY,
captures its frames, moves focus, activates the focused `+1`, requires the
inline component's counter to repaint from `0` to `1`, and cleans up. Text
artifacts are written to `/private/tmp/gama-run-artifacts`.

The same application can emit the `gama` MLIR dialect without a TTY:

```bash
.agents/skills/run-gama/driver.sh mlir
```

For the native macOS application:

```bash
.agents/skills/run-gama/driver.sh apple
```

That last command opens real AppKit windows and remains active until
Command-Q. Automated AppKit behavior is covered separately by the offscreen
shell tests; an unbundled `swift run` process is not proof of packaging,
signing, notarization, or manual accessibility.

## 3. Understand the smallest application

Gama has one application model and multiple hosts. An application declares a
typed scene graph; each backend selects the explicit primary scene unless it
is a multi-window shell.

```swift
import GamaCore
import GamaTUI

struct HelloApp: App {
    init() {}

    var scenes: some Scene {
        Window("Hello", id: "main", role: .primary) {
            VStack(spacing: 1) {
                Text("Hello from Gama").bold()
                Text("Tab moves focus; Ctrl-C quits")
            }
            .padding()
            .border(.rounded, title: "hello")
        }
    }
}

try HelloApp.main(renderer: TUIRenderer())
```

The data flow is always:

```text
App -> SceneBuilder -> primary surface -> ViewBuilder
    -> RenderNode -> LayoutEngine -> LaidOutNode -> backend

backend event -> InputEvent -> FrameHost -> action/focus -> next frame
```

The backend translates native input and presents output. It does not fork
application layout, focus, action, or scene semantics.

## 4. Use macros only as optional syntax

`GamaMacros` adds `@Component`, `@Reactive`, and `#rgb`. The expansion targets
the same public `GamaCore` types used by handwritten code; macros do not create
a second runtime.

```swift
import GamaCore
import GamaMacros

@Component
struct CounterPanel {
    @Reactive var count = 0

    var body: some View {
        HStack {
            Text("count: \(count)")
            Button("+1") { count += 1 }
        }
        .foregroundColor(#rgb("34C9B0"))
    }
}
```

The module selectors emitted by the macros (`GamaCore::View`,
`GamaCore::Signal`, and `GamaCore::Color`) prevent a client declaration named
`GamaCore` from changing lookup.

## 5. Component state persists per surface

Scene content closures are evaluated when a frame is rebuilt, so a component
built inside one is a fresh value every frame. Its `@Reactive` state is not:
the `FrameHost` that owns the surface stores it under the node's structural
identity, and the fresh instance binds to the same storage. Building the
component inline is the correct shape:

```swift
struct CounterApp: App {
    init() {}

    var scenes: some Scene {
        Window("Counter", id: "main", role: .primary) {
            CounterPanel() // Fresh instance each frame; @Reactive state persists.
        }
    }
}
```

`@Reactive` is per-surface: in a `WindowGroup`, every window resolves its
own storage for the same declaration. Hoisting an instance onto the `App`
still works and is still per-surface — each host binds it to its own
storage before invoking an action, and the instance's pre-render value only
seeds each surface's initial value. To share state across surfaces, put a
`Signal` on the `App` and observe it; do not expect a hoisted `@Reactive`
component to do it. `State` remains instance-local.

`@Reactive` is accepted only inside a struct marked `@Component`; anywhere
else the macro reports a compile error rather than silently keeping local
state. Identity is structural, so a branch flip or a positional `ForEach`
reorder drops state; `IdentifiedForEach` and `.stateScope(_:)` pin a subtree
to an identity you choose, and `FrameHost.transientStateIDs` names any node
whose state was reconstructed. See [StateAndIdentity.md](StateAndIdentity.md)
before choosing ownership.

## 6. Connect state that changes outside input callbacks

An action invoked through `FrameHost` already dirties its host, and so does
any write to bound `@Reactive` state, even from a timer or lifecycle handler.
External `Signal` models must connect their changes explicitly:

```swift
let model = Signal(0)
var host = try FrameHost(app: CounterApp())
host.observe(model)

model.set(1)
if host.needsFrame {
    let frame = host.pump(size: Size(width: 80, height: 24))
    // Present frame through the selected backend.
}
```

Use `FrameHost.observe(_:)`, `Signal.subscribe(in:)`, or
`Signal.binding(in:)` for signal-backed models. Use `invalidate()` for an
external source that has no signal. Observation and cancellation belong to
the host; there is no process-global invalidation registry.

## 7. Verify the slice you changed

For ordinary Apple-host development:

```bash
unset TOOLCHAINS
./scripts/check-apple.sh
./scripts/check-boundaries.sh
./scripts/check-docs.sh
./scripts/check-doc-coverage.sh
```

The complete matrix is:

```bash
./scripts/check.sh
```

It deliberately fails when a required SDK, NDK, browser, emulator, MLIR
binary, or platform proof is absent. Do not convert a missing prerequisite
into a passed capability claim. [Verification.md](Verification.md) maps every
gate to the layer it proves.

## Next reading

- [Architecture.md](Architecture.md) — ownership and frame flow.
- [StateAndIdentity.md](StateAndIdentity.md) — state lifetime, collection
  identity, and multi-window ownership.
- [Examples.md](Examples.md) — runnable surfaces by platform.
- [AppleIntegration.md](AppleIntegration.md) — AppKit/UIKit boundaries and
  how SwiftUI, SwiftData, and Foundation Models belong above Gama.
- [Troubleshooting.md](Troubleshooting.md) — toolchain, FileProvider, filter,
  runtime, and evidence failures.
