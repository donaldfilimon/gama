# 0018 — Pointer gestures are host-owned

Status: Accepted. Implemented in GamaCore and unit-tested
(`PointerGestureTests`) on macOS. Phase 2 of the
[dock system design](../superpowers/specs/2026-09-23-dock-system-design.md)
and of the [pointer input plan](../superpowers/plans/2026-09-29-pointer-input.md)
added the backend translations: AppKit and UIKit (`AppleHostPointerTests`
drives AppKit; UIKit is compiled for iOS, tvOS and visionOS but not run),
terminal SGR and the Windows console translator (`PointerBackendTests`, run
on macOS; the Windows console backend itself is not compiled or run here), the WASM v3 pointer exports (Node and
browser smokes) and the C embed pointer entry points (`EmbedPointerABITests`
and the C consumer). Nothing is claimed in
[the capability ledger](../Capabilities.md); rows arrive with backend
evidence at the layer it supports.

## Context

Until now `InputEvent.pointer(_:pressed:)` was the entire pointer model:
`FrameHost.handle` fired the topmost interactive region on press and ignored
the release. There was no move, drag, hover, scroll, modifier, long press or
multi-pointer input. The dock system (dividers, draggable tabs, drop zones)
and any direct-manipulation view need all of them.

Each backend could recognize gestures itself: AppKit has drag events,
UIKit gesture recognizers, the browser Pointer Events, a terminal SGR motion
reports. Doing so would give every backend its own thresholds, its own
cancellation rules and its own idea of a long press, which is exactly the
per-platform fork [0001](0001-own-the-rendering.md) exists to prevent: "Visual
and interaction semantics cannot fork per platform."

## Decision

**Backends translate raw pointer samples; `FrameHost` alone recognizes
gestures.**

1. **One additive event.** `InputEvent.pointerEvent(PointerEvent)` carries a
   phase (down, move, up, cancel, hover, scroll, stationary), a cell
   location, a device kind (mouse, touch, pen), a button, modifiers, a scroll
   delta, a pointer identity and an optional monotonic timestamp. The legacy
   `.pointer(p, pressed:)` stays and means a primary mouse down or up, so no
   consumer breaks.
2. **Opt-in per node.** A view registers a pointer handler for an interactive
   node through `BuildContext.registerPointerHandler`, the way it registers a
   key handler. A press on such a node captures the pointer: every later
   sample from that pointer reaches the node until the gesture ends, and
   samples from any other pointer are ignored. **Nodes without a handler keep
   activate-on-press**, so every existing behavior and golden holds.
3. **Recognition lives in `FrameHost`.** It delivers `PointerGesture`
   phases: pressed, tap, dragBegan, dragMoved, dragEnded, cancelled,
   longPress, hover and scroll. Every pressed is followed by exactly one of
   tap, dragEnded or cancelled. A declined tap falls back to the node's
   registered action, as Enter does for a declined key.
4. **The idiom is the policy.** The host supplies an `InteractionIdiom`
   (phone, pad, desktop, terminal, vision) at creation, and the idiom selects
   the drag threshold and long-press time. On a phone a drag is only possible
   after a long press; travelling the threshold earlier cancels. A terminal
   has no long press.
5. **Time is sampled, not owned.** `FrameHost` has no clock. While a press
   is held it publishes `pointerDeadlineMillis`, and a host with a clock
   delivers a `stationary` sample at that time. Any later sample past the
   deadline also fires the long press, so a host without a timer still gets
   the right answer on release.
6. **Cancellation is total.** An explicit cancel sample, Escape (consumed
   only while a gesture is captured), a resign-key, background, close or
   terminate lifecycle event, and the captured node vanishing on a rebuild
   each end the gesture with `cancelled`. A vanished node is cancelled through
   the handler it last registered.
7. **Hover is environment.** `FrameHost` tracks the topmost interactive node
   under a hovering pointer and publishes it as `EnvironmentValues.hoveredID`,
   requesting a frame only when it changes.
8. **Drop targets and focus requests** are registered the same way
   (`registerDropTarget`, `requestFocus`). Drag phases report the topmost
   drop target under the pointer. A focus request is honored when the next
   `pump` reconciles focus, and dropped if the node is not focusable then.

## Consequences

- Backends stay translators. Phase 2 adds the AppKit, UIKit, terminal SGR,
  Windows console, WASM and C-embed mappings without any backend deciding
  what a sample means, so behavior is identical wherever the samples are.
- `GamaCore` stays stdlib-only and Embedded-safe; the recognizer is plain
  value logic over `InteractiveRegion` frames.
- One pointer is captured at a time. Multi-touch gestures (pinch, rotate) are
  out of scope and would need a superseding or amending record.
- The `stationary` protocol makes long press testable without a clock, and
  the idiom table is the one place to change a threshold.
- Handlers see cells, not points. Sub-cell precision (a smooth divider drag
  on a pixel host) is a later concern of the presentation layer
  ([0017](0017-native-presentation.md)), not of this model.
