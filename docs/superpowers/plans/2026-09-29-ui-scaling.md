# UI Scaling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Gama app's text can be made larger or smaller, following the platform setting where one exists, and the UI refits in cells rather than clipping. Layout can also adapt to the space it has.

**Architecture:** Scale stays in cells. A larger font makes bigger cells and so fewer of them; the host re-measures its cell and sends the surface an ordinary `.resize`, so layout, paint, goldens and every other backend are unchanged. The responsive half (phase 4) is two portable GamaCore additions decided at build time from `EnvironmentValues.surfaceSize`.

**Tech Stack:** Swift 6.5-dev snapshot (`main-snapshot-2026-08-21`), SwiftPM, Swift Testing, AppKit/UIKit, plain JS in `WebHost/`, Kotlin in `Examples/Android`.

**Spec:** `docs/superpowers/specs/2026-09-29-ui-scaling-design.md` (track 1 of the native UI roadmap). Four phases, one PR each.

## Global Constraints

- **Toolchain:** `unset TOOLCHAINS`; `swiftly run swift ...` from the repo root. The manifest stays `swift-tools-version: 6.4`.
- **Scratch:** every track uses its own paths (`GAMA_APPLE_SCRATCH_PATH`, `GAMA_SCRATCH_ROOT`, `GAMA_DOCC_SCRATCH_PATH`, `GAMA_CONCURRENCY_NEGATIVE_SCRATCH_PATH`, and `--scratch-path` for direct tests). `check-mlir.sh` and `check-apple-platforms.sh` hardcode shared paths, so only an integration run invokes them; a track may run the platform gate's single `xcodebuild -scheme GamaAppleUI` per platform with its own `-derivedDataPath` and must report it as that, not as the gate.
- **Portable targets** (GamaCore, GamaPlugin, GamaDraw, GamaEmbed, GamaMLIR) gain no imports and no `nonisolated(unsafe)`.
- **Every new public declaration has a `///` comment.** No allowlist entries.
- **Swift Testing only.** Bind a `~Copyable` host property to a local before `#expect`.
- **TDD:** each task writes the failing test first, runs it red, then implements.
- **No `docs/Capabilities.md` row** is added or strengthened by this plan. A row waits for evidence at the layer it claims.
- **Filters:** `--filter` matches the struct name and a non-matching filter exits 0, so read the test count.

---

## Phase 1: Apple host text size (spec section 1)

Gate for the phase: `scripts/check-apple.sh`, `scripts/check-boundaries.sh`, `scripts/check-docs.sh`, `scripts/check-doc-coverage.sh`, `scripts/check-concurrency-negative.sh`, then `cd GamaStudio && ./tools/check.sh` (the host is a Studio dependency). The integration run adds `scripts/check-apple-platforms.sh` and `scripts/check.sh`.

### Task 1.1: `fontPointSize` and the per-size shared font

**Files:**
- Modify: `Sources/GamaAppleUI/GamaHostView.swift`
- Modify: `Sources/GamaAppleUI/GamaHostAccessibility.swift`
- Create: `Tests/gamaTests/AppleHostFontScaleTests.swift`
- Modify: `docs/Testing.md` (one row)

- [ ] **Step 1: Write the failing tests** in `AppleHostFontScaleTests` (AppKit block):
  - `defaultSizeIsFourteen`: default `fontPointSize == 14` and `cellSize` equals an independently measured "M" probe at 14 pt.
  - `newSizeRefitsTheGrid`: 14 to 28 on a 420x180 view changes `cellSize`, shrinks the grid, leaves `currentDrawList.size` equal to the grid computed from `bounds` and the new cell (no layout pass, no `invalidate`), and advances `producedFrameCount` by exactly one. The jump is large on purpose: `ceil` plus integer division can leave the grid unchanged for a 1 pt step.
  - `sameSizeIsANoOp`: a repeated value changes neither `cellSize`, `producedFrameCount` nor `redrawRequestCount`.
  - `sizeChangeRedrawsEvenWithoutAGridChange`: on a 1x1 pt view (a 1x1 grid at every size) a size change still raises `redrawRequestCount`.
  - `fontsAreSharedPerSize`: hosts at one size share `baseFontIdentifier`; different sizes do not; returning to 14 rejoins the default hosts' font.
  - `sizeChangeClearsStyledCache`: four cached styled fonts drop to zero, and the next styled font is built at the new size.
  - `accessibilityFramesFollowTheCellSize`: after a query arms the cache, a size change yields line-element frames scaled by the new `cellSize`.
  - `sizeIsClamped`: 1 becomes 6, 500 becomes 72, and a second out-of-range write at the same end is a no-op.
  - `sizeBeforeInstallSizesFirstFrame`: a size set before `install` sizes the first frame.
- [ ] **Step 2: Run red:** `swiftly run swift test --scratch-path /private/tmp/gama-t1-scaling-test --filter AppleHostFontScaleTests`. Expect compile errors naming `fontPointSize` and `producedFrameCount`.
- [ ] **Step 3: Implement** in `GamaHostView`:
  - Replace the single static base font with a `@MainActor` static cache keyed by point size, keeping the CoreText rationale comment and extending it: every host at one size shares one immutable font; the clamp bounds the keys.
  - `public var fontPointSize: CGFloat` (get: the font's size; set: clamp to 6...72 first, return if equal, then swap the font, re-measure `cellSize` with the existing "M" probe, clear the styled-font cache, invalidate accessibility geometry, request a redraw unconditionally, send `.resize(gridSize())` and pump, exactly as `layout()` does).
  - Package test seams in the style of `styledFontConstructionCount`: `producedFrameCount` (incremented when the pump produces a frame) and `redrawRequestCount` (incremented by every redraw request). `needsDisplay` is not usable in a test: AppKit does not keep it on a windowless view and does not clear it on an offscreen window.
  - In `GamaHostAccessibility.swift`, `invalidateAccessibilityGeometry()`: mark the snapshot stale, drop the cached line elements (their frames are captured in points at construction), and post `.layoutChanged` only if a client has queried. `refreshAccessibilityIfObserved` alone is not enough, because snapshots compare grid rectangles and would announce nothing when only the cell size changed.
  - Correct the styled-font cache comment: the bound is four entries per size, and a size change empties it.
- [ ] **Step 4: Run green** with the same command, then `--filter AppleHost` to cover the neighbouring font-cache, accessibility and native-region suites.
- [ ] **Step 5:** Add the `AppleHostFontScaleTests.swift` row to the table in `docs/Testing.md`.

### Task 1.2: Backing scale and Dynamic Type

**Files:** `Sources/GamaAppleUI/GamaHostView.swift`, `Tests/gamaTests/AppleHostFontScaleTests.swift`.

- [ ] **Step 1: Failing test** `backingScaleChangeRedraws`: calling `viewDidChangeBackingProperties()` raises `redrawRequestCount` by one and changes neither `cellSize` nor the grid.
- [ ] **Step 2: Implement** the AppKit override (redraw only; cell size is in points). On UIKit, register for `UITraitDisplayScale` in `commonInit` and redraw.
- [ ] **Step 3: Dynamic Type (UIKit only):** `public var followsDynamicType: Bool = false`. Turning it on records the current size as the base, registers for `UITraitPreferredContentSizeCategory` through `registerForTraitChanges` (available at the package minimums iOS 17, tvOS 17, visionOS 1, so the deprecated `traitCollectionDidChange` is not used), and applies `UIFontMetrics.default.scaledValue(for:compatibleWith:)` through `fontPointSize`. Turning it off unregisters and restores the base.
- [ ] **Step 4:** Add the UIKit block to the test file (`UIKitHostDynamicTypeTests.followsContentSizeCategory`, using `traitOverrides`). No gate builds `GamaTests` for a UIKit platform, so it is compiled by nothing today; say so in the file and in the PR.
- [ ] **Step 5: Compile UIKit:** `xcodebuild -scheme GamaAppleUI -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/gama-t1-scaling-ios-derived CODE_SIGNING_ALLOWED=NO -quiet build`, then the same for tvOS and visionOS with their own derived-data paths. This is the platform gate's command at a private path, not the gate.
- [ ] **Step 6: Phase gate** (above), then commit: `feat(apple-ui): settable text size with per-size shared fonts`.

## Phase 2: macOS shell zoom menu (spec section 1, "macOS text size")

**Files:** `Sources/GamaAppleShell/GamaShell.swift`; `Tests/gamaTests/AppleShellTests.swift`.

- [ ] **Step 1: Failing test** in `AppleShellTests`: a package-visible shell action for Bigger, Smaller and Actual Size steps the key window's host `fontPointSize` by 1 pt (to 15, to 13, back to 14) and a step past a clamp end stays at the end. Test the action routing directly; no menu is clicked.
- [ ] **Step 2: Implement** a View menu in `installMainMenu` with Bigger (Command-+), Smaller (Command--) and Actual Size (Command-0). The step (1 pt) and the actual size (14 pt) are constants in the shell, not the host. The actions resolve the key window's `GamaHostView`.
- [ ] **Step 3: Gate:** phase 1's list plus `GamaStudio/tools/check.sh`. Commit: `feat(apple-shell): View menu text size commands`.

## Phase 3: Web `setFontSize` and the Android density fix (spec sections 2 and 3)

**Files:** `WebHost/gama.js`, `WebHost/index.html`, the browser smoke driver under `scripts/`, `Examples/Android/app/src/main/java/com/gama/example/MainActivity.kt`, `docs/backends/CEmbed.md`.

- [ ] **Step 1: Failing smoke:** extend the browser smoke to call `setFontSize(28)` and assert that a resize arrives with a smaller grid. Run its `--self-test` first, as `check-wasm.sh` does.
- [ ] **Step 2: Implement** the `--gama-font-size` CSS custom property (default `14px`) and `setFontSize(px)`, which sets it, re-runs `cellMetrics()` and calls `notifyResize()`, the path `document.fonts.ready` already uses. Add A-/A/A+ buttons to the demo page. `Sources/GamaWASM` and the export tiers do not change.
- [ ] **Step 3: Android:** replace the pixel `textSize = 24f` with `TypedValue.applyDimension(COMPLEX_UNIT_SP, 14f, displayMetrics)` and re-derive the cell and call the embed resize on configuration change. Evidence is `check-android.sh` building the example; no runtime proof is claimed.
- [ ] **Step 4:** One paragraph in `docs/backends/CEmbed.md`: the C ABI stays in cells, and scaling means resizing in cells.
- [ ] **Step 5: Gate:** phase 1's list plus `scripts/check-wasm.sh` (node and the pinned toolchain are prerequisites; a missing one is reported as not run) and `scripts/check-android.sh` with `ANDROID_NDK_HOME` set. Commit per half.

## Phase 4: `widthClass` and `ViewThatFits` (spec section 5)

Touches only GamaCore; it can run in parallel with phases 1-3.

**Files:** `Sources/GamaCore/View.swift` (`EnvironmentValues`), a new `Sources/GamaCore/ViewThatFits.swift`, `Tests/gamaTests/ResponsiveLayoutTests.swift`, `docs/Testing.md`.

- [ ] **Step 1: Failing tests** in `ResponsiveLayoutTests`: `widthClass` at 59, 60, 119 and 120 columns and with no `surfaceSize`; `ViewThatFits` picks the first candidate that fits, falls back to the last, and yields `CellSerializer` goldens at 120x40, 80x24 and 40x20.
- [ ] **Step 2: Implement** `EnvironmentValues.widthClass` (`compact` below 60 columns, `wide` from 120, `regular` between; the thresholds are public constants) and `ViewThatFits`, a primitive (`Body = Never_`) that measures each candidate with `LayoutEngine.measure` against the proposed size and adds no `RenderNode` case. Its documentation states the limit: it fits the surface or the size it is proposed, not a frame solved later.
- [ ] **Step 3: Gate:** phase 1's list plus `scripts/check-embedded.sh`. If the artifact leaves its band, re-measure `scripts/embedded-size-baseline.txt` deliberately and say so; never widen the tolerance. Commit: `feat(core): widthClass and ViewThatFits`.

## Deliberately not in this plan

Point-based layout (track 3), per-view font sizes, a type scale or theme, scaling inside native regions, and any `docs/Capabilities.md` row.
