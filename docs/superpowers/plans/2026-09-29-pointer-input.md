# Pointer Input Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give Gama a rich, host-owned pointer model (move, drag, hover,
scroll, long press, modifiers, capture) and teach every backend to feed it,
without breaking the existing `InputEvent.pointer(_:pressed:)` contract.

**Scope:** phases 1 and 2 of the
[dock system design](../specs/2026-09-23-dock-system-design.md) (sections 1
"Pointer input model" and 2 "Backend translation", plus the matching part of
its Testing section). `GamaDock` (phase 3), native regions in panes
(phase 4) and gama-studio adoption (phase 5) are **not** in this plan. This is
track 2 of the [native UI roadmap](../specs/2026-09-29-native-ui-roadmap-design.md).

**Architecture:** One additive `InputEvent.pointerEvent(PointerEvent)` case.
Recognition (capture, thresholds, long press, tap versus drag, cancel, hover)
lives in `FrameHost`, so every backend only translates platform events and
behavior cannot fork per backend. Views opt in by registering a pointer
handler for an interactive node through `BuildContext`, exactly as they
register key handlers today. The legacy `.pointer(p, pressed:)` event maps
onto a primary mouse down or up, so regions without a handler keep today's
activate-on-press and every existing golden holds. Policy is ADR 0018.

**Tech stack:** Swift 6.5-dev snapshot (`main-snapshot-2026-08-21`), SwiftPM,
Swift Testing. Phase 2 adds AppKit/UIKit, the SGR terminal decoder, the
Windows console translator, the WASM exports and the C embed ABI.

## Global constraints

- `unset TOOLCHAINS`; the manifest stays `swift-tools-version: 6.4`.
- `GamaCore` stays stdlib-only and Embedded-safe (`scripts/check-embedded.sh`
  compiles it alone): no Foundation, no `any`, no `nonisolated(unsafe)`.
- Every new public declaration carries a `///` comment; no allowlist entries.
- Swift Testing only. `#expect` cannot read a bare property off a
  `~Copyable` host: bind to a local first.
- Each gate gets its own scratch root (`GAMA_APPLE_SCRATCH_PATH`,
  `GAMA_SCRATCH_ROOT`, `GAMA_DOCC_SCRATCH_PATH`,
  `GAMA_CONCURRENCY_NEGATIVE_SCRATCH_PATH`).
- No `docs/Capabilities.md` row moves to a stronger layer. Phase 1 adds no
  row: it is implemented and unit-tested only, and no backend emits the new
  event yet.

---

## Phase 1: pointer model in GamaCore (this branch, chunk 1)

**Files:**
- Create `Sources/GamaCore/PointerGesture.swift`: `PointerEvent`,
  `InteractionIdiom`, `PointerPolicy`, `PointerGesture`.
- Modify `Sources/GamaCore/Runtime.swift`: `InputEvent.pointerEvent`.
- Modify `Sources/GamaCore/View.swift`: `BuildContext.registerPointerHandler`,
  `registerDropTarget`, `requestFocus`; `EnvironmentValues.hoveredID`.
- Modify `Sources/GamaCore/FrameHost.swift`: idiom, recognizer, capture,
  hover, focus requests, `pointerDeadlineMillis`.
- Modify `Sources/GamaCore/HostPump.swift`: forward `pointerDeadlineMillis`.
- Create `Tests/gamaTests/PointerGestureTests.swift`.
- Create `docs/adr/0018-pointer-gestures-are-host-owned.md`; add its row to
  `docs/adr/0000-index.md`.

### Task 1.1: the event and policy types

- [ ] Write failing tests: `PointerEvent` defaults (mouse, button 0,
  pointer 0, no modifiers, zero scroll, no timestamp); the idiom table
  (desktop 1 cell / 500 ms; terminal 1 cell / none; pad 2 cells / 400 ms;
  phone drag only after a 500 ms long press; vision follows pad until a
  vision host measures otherwise).
- [ ] Run them and see the build fail on the missing types.
- [ ] Implement `PointerGesture.swift`; add `InputEvent.pointerEvent`.

### Task 1.2: registration hooks

- [ ] Failing test: a host-less `BuildContext()` accepts all three hooks as
  no-ops, and `EnvironmentValues().hoveredID` is `nil`.
- [ ] Add the three `BuildContext` closures with no-op defaults and the
  `hoveredID` environment value.

### Task 1.3: recognition in FrameHost

Tests first, one behavior per test, driven through `FrameHost.handle` with a
test app whose primitive registers a pointer handler and logs every gesture:

- [ ] legacy `.pointer(p, pressed: true)` still activates a plain `Button`
  on press, and a release does nothing;
- [ ] a down on a handler region delivers `.pressed`, captures it, and a
  release inside the threshold delivers `.tap`; a declined tap falls back to
  the node's registered action;
- [ ] per idiom: a move below the threshold stays a press; at the threshold it
  delivers `.dragBegan`, later moves `.dragMoved`, the release `.dragEnded`;
- [ ] capture: moves and the release outside the region still reach it, and a
  second pointer id is ignored while one is captured;
- [ ] long press: the deadline is `down timestamp + policy`, exposed as
  `pointerDeadlineMillis`; a `stationary` sample at or after it delivers
  `.longPress` once and clears the deadline; terminal has none; a release
  after a long press ends with `.cancelled`, never `.tap`;
- [ ] phone: movement past the slop before the long press cancels; after the
  long press it drags;
- [ ] cancel paths: `.cancel`, Escape (consumed), a resign-key or background
  lifecycle event, and the captured node vanishing on rebuild each deliver
  exactly one `.cancelled` and release the capture;
- [ ] invariant: every `.pressed` is followed by exactly one of `.tap`,
  `.dragEnded`, `.cancelled`;
- [ ] drop target: `dragMoved`/`dragEnded` carry the topmost registered drop
  target under the pointer;
- [ ] hover: `hoveredID` reaches the environment, the host is dirty only when
  it changes, and a vanished hovered node clears silently;
- [ ] scroll reaches the innermost handler region under the pointer;
- [ ] `requestFocus` from a handler moves focus on the next `pump`; a request
  for a node that is not focusable is dropped.
- [ ] Implement; iterate to green.

### Task 1.4: ADR 0018 and the index row

- [ ] Write the ADR (Context / Decision / Consequences), status Accepted,
  implementation unit-tested only.
- [ ] Add the `0000-index.md` row.

### Task 1.5: gate and commit

- [ ] `scripts/check-apple.sh`, `scripts/check-boundaries.sh`,
  `scripts/check-docs.sh`, `scripts/check-doc-coverage.sh`,
  `scripts/check-concurrency-negative.sh`, `scripts/check-embedded.sh`,
  `scripts/check-evidence-freshness.sh`; `GamaStudio/tools/check.sh` only if
  the Apple host or layout changed (phase 1 does not). If the Embedded size
  band moves, re-measure `scripts/embedded-size-baseline.txt` deliberately and
  say so in the commit.
- [ ] Commit only on green.

## Phase 2: backend translation (chunk 2)

Pure event mapping; no backend decides anything. Each step is test-first.

- [ ] **Apple host** (`Sources/GamaAppleUI/GamaHostView.swift`). AppKit:
  `mouseDragged`, `mouseMoved` through a tracking area installed in
  `commonInit` and `updateTrackingAreas`, `mouseExited` (a hover outside the
  grid), right and other buttons, `scrollWheel` with precise deltas
  accumulated into whole cells, `modifierFlags`, `event.timestamp` in
  milliseconds. UIKit: `touchesMoved` tracking the first touch by identity,
  `UITouch.type` to kind, `UIHoverGestureRecognizer` for iPad hover, a scroll
  pan recognizer. A one-shot timer delivers the `stationary` sample at
  `pointerDeadlineMillis`. The host is created with its idiom (`desktop` on
  macOS, `pad` or `phone` from the trait collection, `vision` on visionOS).
  Test: an AppKit host drag test in `AppleHostTests`.
- [ ] **Terminal**: `Sources/GamaDraw/TerminalCapabilities.swift` enables and
  disables `?1002h` (button-held motion) beside the existing mouse modes.
  `Sources/GamaTUI/Terminal.swift` decodes SGR button bits (button, +4
  shift, +8 alt, +16 ctrl, +32 motion, 64-67 wheel) into `PointerEvent`; the
  Windows console translator handles `MOUSE_MOVED` and `MOUSE_WHEELED` and
  reads control-key state for modifiers. The TUI host uses the `terminal`
  idiom. Tests: SGR decode table, `WindowsTerminalTests`, `?1002h` in
  `TerminalCapabilityTests`.
- [ ] **WASM** (`Sources/GamaWASM/WASMHost.swift`, `WebHost/gama.js`): a new
  `gama_web_v3_pointer_event(...)` export (v1 and v2 unchanged), Pointer
  Events with `setPointerCapture`, and `wheel`. Gate: `scripts/check-wasm.sh`
  including the browser smoke; if node or the toolchain is missing, report
  NOT RUN.
- [ ] **C embed** (`Sources/GamaEmbed/CInterface.swift`,
  `Sources/GamaEmbedABI/include/GamaEmbed.h`, `Examples/CEmbed/main.c`):
  additive `gama_embed_v1_pointer_event` and `gama_embed_v1_pointer_deadline`
  plus `GAMA_EMBED_POINTER_*` constants; `abi_version` stays 1 and `main.c`
  exercises both. Gate: `scripts/check-c-abi.sh` (`-Werror`).
- [ ] Gates: the phase 1 list plus `check-c-abi.sh`, `check-wasm.sh` and
  `GamaStudio/tools/check.sh` (the Apple host changes). Integration runs
  `scripts/check.sh`, `check-mlir.sh` and `check-apple-platforms.sh`; hosted
  runs are billing-locked and count as unmeasured.

## Deliberately not in this plan

- A public `View` modifier for pointer gestures. Phase 3 (`GamaDock`) is its
  first consumer and should shape it; until then a primitive registers a
  handler through `BuildContext` directly.
- Multi-touch gestures (pinch, rotate). One pointer is captured at a time.
- Capability ledger rows. Rows arrive with backend evidence, at the layer
  that evidence supports.
