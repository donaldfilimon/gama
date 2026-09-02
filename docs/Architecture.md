# Architecture and ownership

Status: Current architecture guide for the implemented retained renderer.
Platform-specific proof remains in [Capabilities.md](Capabilities.md); dated
specifications under `superpowers/` are design history, not a second status
ledger.

Gama keeps one backend-neutral application model and pushes platform-specific
work to narrow edges. The most important rule is ownership: one live surface
owns one noncopyable host, and that host owns the focus, actions,
subscriptions, dirty state, and frames for that surface.

## End-to-end frame flow

```text
App
  -> @SceneBuilder
  -> one explicit primary scene plus optional auxiliary scenes
  -> @ViewBuilder or GamaMacros
  -> RenderNode
  -> LayoutEngine
  -> LaidOutNode
  -> CellPainter
  -> CellBuffer
  -> DrawList
  -> TUI | AppKit/UIKit | WASM | C/Android | MLIR

native input
  -> backend translation
  -> InputEvent
  -> FrameHost
  -> focus/key/action/lifecycle handling
  -> dirty state
  -> next pump
```

Layout, focus traversal, hit testing, actions, and application lifecycle are
shared semantics. A backend translates events, chooses metrics, schedules
frames, and presents output; it does not implement a private application
runtime.

## Module boundaries

| Layer | Owns | Must not own |
| --- | --- | --- |
| `GamaCore` | scenes, views, identity, state, layout, events, `FrameHost` | Foundation, platform UI, POSIX, WinSDK, global registries |
| `GamaPlugin` | static plugin manifests, grants, scoped capability handles | platform services or dynamic loading |
| `GamaPlatformServices` | Foundation-backed clock, random, files, environment, logging | renderer or application semantics |
| `GamaDraw` | cells, painting, draw lists, versioned binary codec | native windows or input loops |
| `GamaTUI` | terminal ownership, decoding, differential presentation | a separate layout or focus engine |
| `GamaAppleUI` | AppKit/UIKit host views, event translation, drawing | application window policy |
| `GamaAppleShell` | macOS app and multi-window lifecycle | portable layout or scene semantics |
| `GamaWASM` | exported browser reactor around one installed host | filesystem-capable general WASI runtime |
| `GamaEmbed` | opaque contexts and versioned C entry points | process-global framework state |
| `GamaMLIR` | deterministic textual lowering | a Swift compiler frontend |

Portable targets depend inward. Application, demo, example, and test targets
may import `GamaPlatformServices`; framework targets use service interfaces.
The boundary gate checks these rules mechanically.

## Scene compilation

`App.scenes` is evaluated once to compile a closed scene graph. Every app must
declare exactly one scene with `role: .primary`.

- Single-surface hosts select that primary scene.
- `GamaAppleShell` also owns auxiliary and payload-addressed windows.
- `Window` is a singleton declaration: reopening focuses its existing live
  instance.
- `WindowGroup` uses a typed payload key and may create one instance per
  distinct payload.
- `WindowInstanceID` distinguishes live instances from their declaration's
  stable `SceneID`.

Invalid configurations throw `SceneConfigurationError` before presentation.
No backend guesses which scene should be primary.

## One host per live surface

`FrameHost` is `~Copyable`. Copying it would share reference-backed action
tables, subscriptions, and dirty state while pretending to create an
independent surface, so the compiler prevents that shape.

Each host owns:

- The stable scene declaration and live window-instance identities.
- Per-frame actions and key handlers.
- Focus identity and the current focusable regions.
- Duplicate interactive-identity diagnostics.
- Host-local subscriptions and cancellation.
- Dirty state, latest size, and quit intent.

`AppRuntime` is also noncopyable. Poll-style renderers such as the terminal
use it as their blocking loop. Retained hosts such as AppKit, UIKit, the
browser reactor, and C embedding retain a `FrameHost` and call
`handle(_:)`/`pump(size:)` from their native scheduler.

## Frame construction

Every pump performs the same sequence:

1. Clear the dirty flag and start a new action-registration pass.
2. Render the scene content into a `RenderNode` tree.
3. Measure and place it into a `LaidOutNode` tree.
4. Collect interactive regions and detect duplicate `NodeID` values.
5. Reconcile focus by identity rather than array position.
6. Rebuild once when focus reconciliation changes the environment so the
   returned frame already contains the correct focus appearance.

`RenderNode.group` is the flattening sentinel emitted by tuples and
`ForEach`. `RenderNode.overlay` is the `ZStack` lowering and always layers;
it is never flattened into a parent stack.

## Input and lifecycle

Backends normalize native events into `InputEvent`:

- Tab and Shift-Tab traverse focus order.
- Arrow keys choose a spatial neighbor, with tab-order fallback.
- Enter and Space invoke the focused action.
- Pointer presses hit-test the topmost interactive region.
- Resize records the new size and dirties the host.
- Lifecycle events may address one scene/window instance.
- Ctrl-C and Ctrl-Q request portable termination.

An action is registered while a frame is built and belongs only to that
host's action table. There is no global lookup that could invoke an action on
another window or application.

## State and invalidation

`Signal`, `Binding`, `State`, and `SubscriptionContext` are host-confined.
`Signal` and selected runtime types explicitly declare `~Sendable`; unavailable
`@unchecked Sendable` conformances preserve a named compiler diagnostic for
attempted laundering.

Input-driven actions already cause another frame. Out-of-band changes use:

- `FrameHost.observe(_:)`
- `Signal.subscribe(in:)`
- `Signal.binding(in:)`
- `FrameHost.invalidate()` for a non-signal source

Observation is idempotent per signal instance. Cancelling one host's
subscriptions cannot detach another host. See
[StateAndIdentity.md](StateAndIdentity.md) for component lifetime and
multi-window consequences.

## Drawing and foreign hosts

`CellPainter` turns laid-out nodes into a `CellBuffer`; `DrawList.from` turns
the buffer into coalesced drawing commands. Native and foreign hosts consume
the same commands.

The C/Android binary representation is separately versioned. It starts with a
20-byte little-endian header containing `GAMA`, version `1`, dimensions, and a
command count. Contexts own their frame bytes; a returned pointer remains valid
only until that context's next frame request or destruction.

The wire format is a compatibility boundary. Do not infer that a Swift enum
layout, `MemoryLayout`, or in-process representation is stable enough to send
across it.

## Plugins and services

Tier-1 plugins are statically linked Swift values. Installation checks a
manifest against an exact, deny-by-default capability table and provides only
the handles granted to that plugin. Removing or replacing a plugin revokes its
commands and subscriptions.

This is useful least-authority structure inside one trusted process. It is not
a sandbox. Dynamic-library and out-of-process tiers require separate designs
and are not implied by the static plugin API.

## Extending Gama safely

When adding a feature, choose the narrowest owning layer:

- Application meaning or layout belongs in `GamaCore` only when every backend
  must share it and it can remain stdlib-only.
- Drawing coalescing or codec work belongs in `GamaDraw`.
- Event decoding, native metrics, scheduling, and presentation belong in a
  backend.
- Foundation-backed facilities belong behind a service interface and in
  `GamaPlatformServices`.
- AppKit/SwiftUI chrome, SwiftData persistence, and Foundation Models sessions
  belong in an Apple application layer, not in the portable renderer.

Then run the affected focused gate plus the boundary, documentation, and
complete acceptance gates described in [Verification.md](Verification.md).
