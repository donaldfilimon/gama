# Native UI roadmap: platform controls, scaling, pointer input, other hosts

**Status: proposed, awaiting owner review (2026-09-29). Nothing new is
built.** The owner asked for native macOS and Apple-platform controls, SwiftUI
and SwiftData integration, UI scaling, rich pointer input, and other native
hosts in one request. That is five projects with separate specs, not one. This
document is the split: what each track is, what it depends on, which tracks
can run in parallel, and where each one's design lives. It decides no
architecture of its own; each track's spec does that.

ADR 0017 (native presentation) was accepted by the owner on 2026-09-29.

## What exists today

- Layout is integer cells end to end (`Sources/GamaCore/Geometry.swift`).
  `LayoutMetrics` (`Sources/GamaCore/LayoutMetrics.swift`) is the one seam
  for other units; only tests pass anything but `.cell`.
- The Apple host draws a fixed 14 pt monospaced font. It measures the cell
  once, when the view is created, and has no text-size, Dynamic Type, or
  backing-scale handling (`Sources/GamaAppleUI/GamaHostView.swift`).
- The web host sizes its grid from a 14 px CSS font. Browser zoom changes the
  cell count and nothing else (`WebHost/gama.js`, `cellMetrics()`).
- The pointer model is `InputEvent.pointer(Point, pressed:)` only: no drag,
  hover, scroll, or modifiers.
- Native regions (ADR 0016) are built and exercised locally on macOS only.
  Native presentation (ADR 0017) has plan Task 1, `LayoutMetrics`, and
  nothing else.
- No backend other than the Apple host has any native-control hook.

## The five tracks

| # | Track | Design | Depends on |
|---|---|---|---|
| 1 | UI scaling | [2026-09-29-ui-scaling-design.md](2026-09-29-ui-scaling-design.md) (new) | nothing |
| 2 | Rich pointer input | [dock spec](2026-09-23-dock-system-design.md) sections 1-2 and phases 1-2 | nothing |
| 3 | Native macOS controls | [native presentation spec](2026-09-23-native-presentation-design.md) and [plan](../plans/2026-09-23-native-presentation.md), Tasks 2-12 | 0017 accepted |
| 4 | SwiftUI and SwiftData | a new spec, written after track 3's host type exists | 3 for the native variant |
| 5 | Other native hosts | a new spec per host: UIKit (iOS, iPadOS, visionOS) first, then Android Views, then Windows | 3 |

### Track 1: UI scaling

The user can make text bigger or smaller and the UI refits instead of
clipping, on every GUI host. Scaling stays in cells: a larger font means
fewer, bigger cells, the same way browser zoom already behaves on the web.
Fractional units belong to track 3's `LayoutMetrics` host, not here. Track 1
also adds build-time responsive layout driven by `surfaceSize`.

### Track 2: Rich pointer input

Drag, hover, scroll, modifiers, and long press through
`InputEvent.pointerEvent(PointerEvent)`. Recognition is centralized in
`FrameHost`, and every backend translates its platform events. The dock spec
already designs this and names the ADR "0017 Pointer gestures are
host-owned". That number now belongs to native presentation, so the pointer
ADR becomes **0018** and the dock ADR becomes **0019**. The dock spec is
updated to match. Only its phases 1-2 are in this track; the `GamaDock`
target (phases 3-5) stays a later, separate step.

### Track 3: Native macOS controls

Resume the existing plan at Task 2 (`FrameHost` carries `LayoutMetrics`),
through the `ControlDescriptor` side table, the presentation tree and diff,
`AppKitLayoutMetrics`, `GamaNativeHostView`, shell opt-in, and a `--native`
demo flag. `GamaNativeHostView` is a separate type from `GamaHostView`, which
keeps this track out of the file tracks 1 and 2 edit.

### Track 4: SwiftUI and SwiftData (assumed scope; owner to confirm)

- **SwiftUI embedding:** a `GamaView` that wraps the host view through
  `NSViewRepresentable` and `UIViewRepresentable`, so a SwiftUI app can show a
  Gama surface. It lives in a new Apple-only target, never in a portable one.
  It first wraps `GamaHostView`, then `GamaNativeHostView` once track 3
  lands.
- **SwiftData persistence:** a store in the platform-services layer that saves
  and restores selected `@Reactive` state through SwiftData models. The
  portable core gains no import; `GamaPlatformServices` or a new Apple-only
  services target owns it.
- **Deferred:** Gama hosting SwiftUI views as controls. That is a variant of
  track 3's presentation mapping and waits for it.
- **Specs:** [SwiftUI embedding design](2026-09-29-swiftui-embedding-design.md)
  (built on a feature branch, wrapping `GamaHostView` first) and the
  [SwiftData persistence draft](drafts/2026-09-29-swiftdata-reactive-persistence-draft.md)
  (open questions only).

### Track 5: Other native hosts

A `UIKitNativeHostView` following track 3's mapping table (iOS, iPadOS,
visionOS; UIKit scene ownership is already listed as deferred scope in
`tasks/todo.md`). Then an Android Views host over the existing JNI example.
Windows stays blocked: no Windows Swift 6.5-dev toolchain exists and no
Windows runner is registered. The UIKit mapping and its open questions are in
the [UIKit native host draft](drafts/2026-09-29-uikit-native-host-draft.md).

## Parallel execution

Tracks 1 and 2 are independent and can be built by parallel agents, each in
its own worktree. Both edit `Sources/GamaAppleUI/GamaHostView.swift`, but in
disjoint regions: track 1 the font and cell measurement, track 2 the event
overrides. Whichever lands second rebases onto the first. Track 3 can run
alongside them because its host is a new file; its Task 2 edits
`FrameHost.swift`, which track 2 also edits, so tracks 2 and 3 merge in
sequence. Tracks 4 and 5 follow track 3.

Every track lands as its own PR on `main` and is gated locally by
`scripts/check-apple.sh` and then `scripts/check.sh`, reading each verdict
line. `GamaStudio/tools/check.sh` also runs after any change to the Apple
host or layout. Hosted runs are billing-locked for GitHub-hosted jobs; the
self-hosted `gama` runner covers the macOS and Embedded jobs. No row in
`docs/Capabilities.md` moves without evidence at the layer it claims.

## Out of scope

Theme and design tokens, a Windows GUI backend, a Linux desktop backend, the
`GamaDock` target itself, a `ScrollView` (it needs track 2 first), IME and
bidi on the cell path.
