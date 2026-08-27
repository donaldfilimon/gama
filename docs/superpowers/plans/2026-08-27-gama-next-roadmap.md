# Gama Stabilization, Wave-2, and Liquid Glass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: use `superpowers:subagent-driven-development` or `superpowers:executing-plans` to implement this plan task-by-task. Preserve the existing worktrees and active-session edits; never overwrite a branch merely because its local worktree is behind its remote tip.

**Goal:** Safely integrate Gama's active wave-1 work, repair its hosted-evidence process, complete the approved structural modernization, and add an opt-in Apple-family SwiftUI/Liquid Glass layer without weakening the retained-renderer architecture.

**Architecture:** `GamaCore` remains the stdlib-only retained UI engine and the sole owner of application semantics. AppKit/UIKit hosts continue to render `DrawList`; the new `GamaSwiftUI` target embeds those hosts and adds native SwiftUI chrome around them. Liquid Glass is presentation-only, gated to OS 26+, and never enters `GamaCore`, backend-neutral IR, or non-Apple builds.

**Tech Stack:** SwiftPM, pinned Apple Swift 6.5-dev snapshot `main-snapshot-2026-08-21`, Swift 6 language mode, Swift Testing, AppKit/UIKit, SwiftUI/Observation, GitHub Actions, DocC, Instruments/xctrace, Developer ID signing and notarization.

**Specs:**

- `docs/superpowers/specs/2026-08-27-plugin-runtime-design.md`
- `docs/superpowers/specs/2026-08-27-packaging-design.md`
- `docs/superpowers/specs/2026-08-27-frame-pump-unification-design.md`
- `docs/superpowers/specs/2026-08-27-signal-redesign-design.md`
- Create `docs/superpowers/specs/2026-08-27-gama-swiftui-liquid-glass-design.md`
- Save this approved plan to `docs/superpowers/plans/2026-08-27-gama-next-roadmap.md` before implementation.

## Global Constraints

- Treat `donaldfilimon/gama` and `origin/main` as remote/history authority; do not conflate this Swift framework with the unrelated Qt project.
- Preserve all current platform targets: macOS, iOS, tvOS, visionOS, TUI, WASM, C embedding, Android, Embedded, MLIR, and native Windows console.
- Keep `Package.swift` at `// swift-tools-version: 6.4`; the compiler—not manifest grammar—is pinned to Swift 6.5-dev.
- Before every Swift command: `unset TOOLCHAINS`. Use `swiftly run swift …` for ad-hoc commands and the repository scripts for authoritative gates.
- Route all SwiftPM test/build scratch data outside the iCloud-managed checkout, normally under `/private/tmp`.
- Never run `git gc`, `git fsck`, `git prune`, or `git repack` in `/Users/donaldfilimon/Desktop/Gama`.
- `GamaCore` remains stdlib-only and must not import Foundation, AppKit, UIKit, SwiftUI, Observation, Synchronization, Darwin, Glibc, or WinSDK.
- Tests remain Swift Testing only; do not reintroduce XCTest.
- Do not merge any PR until all six acceptance jobs are green, the branch is current with `main`, and unresolved review threads are closed.
- After each merge, wait for the merge-SHA `main` acceptance run to complete before merging the next PR.
- Keep Windows' checksum-pinned Swift 6.4.x exception until swift.org publishes a usable Windows 6.5-dev snapshot.
- Liquid Glass follows Apple's native composition model: `glassEffect`, `GlassEffectContainer`, consistent shapes, non-interactive glass for non-controls, and material fallbacks on older systems. [Apple's Liquid Glass guidance](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views) is the API authority.

## Task 1: Repair Governance and Recover the Desktop Checkout

### 1.1 Preserve the existing local work

The Desktop checkout is behind `origin/main` and has uncommitted `.gitignore`, `CLAUDE.md`, and `Package.resolved` changes.

- Create `wip/preserve-desktop-edits-20260827` at the current local `main`.
- Commit the three files together with `wip: preserve desktop checkout edits`; do not push this preservation branch.
- Switch back to `main` and fast-forward only:

```bash
git fetch origin
git switch main
git merge --ff-only origin/main
```

- Create `chore/desktop-guidance-hygiene` from the updated `main`.
- Reapply and review only the intentional `.gitignore` and `CLAUDE.md` changes from the preservation branch.
- Keep the hash-only `Package.resolved` change on the preservation branch unless resolving the current manifest with the pinned compiler reproduces it. Never hand-edit `originHash`.
- Put the reviewed guidance changes through their own small PR rather than mixing them into feature branches.

### 1.2 Make the acceptance matrix enforceable

Update the existing GitHub ruleset “Require pull requests for main” without removing its current deletion, non-fast-forward, or PR requirements.

Add strict required-status-check enforcement for these exact contexts:

- `macOS / Apple Swift 6.5-dev`
- `Linux / Swift 6.5-dev native and static SDK`
- `WebAssembly / Swift 6.5-dev SDK and runtime`
- `Android / Swift 6.5-dev embedding and emulator`
- `Embedded / exact Swift 6.5-dev snapshot`
- `Windows / native console Swift 6.4.x (main-snapshot unavailable)`

Requirements:

- Strict/up-to-date branch policy enabled.
- No ordinary merge or auto-merge bypass.
- A pull request remains mandatory.
- Preserve the current zero-review workflow unless a separate review-policy change is explicitly requested.

Verify the ruleset through the GitHub API after updating it; the returned rule set must contain all six contexts.

### 1.3 Preserve post-merge evidence

Create `ci/preserve-main-acceptance-runs` from current `main` and change `.github/workflows/ci.yml` to:

```yaml
concurrency:
  group: gama-${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}
```

This retains cancellation for superseded PR commits while allowing every `main` push run to finish.

Keep `ASAN_OPTIONS=detect_leaks=0` for `swift test --sanitize address`. Do not reopen the closed broad `leak:XCTest` suppression branch: because all test allocations run beneath XCTest harness frames, that pattern lacks a negative-control proof that a real Gama leak would still fail.

Land the current ASan/root-cause ledger PR before feature work, then land the concurrency PR. Each must pass all six checks and receive a completed post-merge `main` run.

### 1.4 Establish the clean baseline

Run:

```bash
cd /Users/donaldfilimon/Desktop/Gama
unset TOOLCHAINS
swiftly run swift --version
./scripts/check-apple.sh
./scripts/check-apple-platforms.sh
./scripts/check-boundaries.sh
./scripts/check-docs.sh
./scripts/check-doc-coverage.sh
```

Expected compiler identity: Apple Swift 6.5-dev, Swift revision `95c5142e84b82c1`.

Record separately:

- Local gate results.
- Six hosted PR jobs.
- Completed merge-SHA `main` job.
- GitHub Pages HTTP 200 from `https://donaldfilimon.github.io/gama/`.

Commit: `ci: require complete Gama acceptance evidence`.

## Task 2: Integrate Wave-1 Work in a Fixed Order

Use one current, clean worktree per PR. Before touching a branch, fetch its remote tip and confirm whether another active session advanced it. Do not assume a stale local worktree is authoritative.

### 2.1 Merge documentation catalogs

Land serially:

1. PR #28 — backend DocC catalogs.
2. PR #29 — GamaEmbed DocC catalog.

For each PR:

- Merge or rebase current `main` into the branch.
- Resolve only ledger/documentation overlaps.
- Run `check-docs.sh`, `check-doc-coverage.sh`, `check-boundaries.sh`, and `check-apple.sh`.
- Require all six hosted jobs.
- Merge, wait for the `main` run, then begin the next PR.

### 2.2 Merge packaging V1

Update PR #32 after both DocC PRs land. Preserve its existing contract:

- `Distribution/` manifests contain identity and branding only.
- `bundle-web.sh` assembles the deployable browser directory and runs the browser smoke.
- `bundle-macos.sh` stages `Gama Demo.app` outside iCloud, validates the plist, ad-hoc signs, performs deep/strict codesign verification, and runs `gama-apple-demo --smoke`.
- `release-macos.sh` fails closed unless both signing and notary environment variables exist.
- CI uploads the WASM site and ad-hoc macOS artifact; CI does not claim notarization.

Required local checks:

```bash
unset TOOLCHAINS
./scripts/check-apple.sh
./scripts/check-wasm.sh
GAMA_DIST_ROOT=/private/tmp/gama-dist ./scripts/bundle-web.sh
GAMA_DIST_ROOT=/private/tmp/gama-dist ./scripts/bundle-macos.sh
```

After the green merge, run the credentialed path using the already configured environment:

```bash
test -n "${GAMA_CODESIGN_IDENTITY:?GAMA_CODESIGN_IDENTITY is required}"
test -n "${GAMA_NOTARY_PROFILE:?GAMA_NOTARY_PROFILE is required}"
GAMA_DIST_ROOT=/private/tmp/gama-dist ./scripts/release-macos.sh
```

Record `codesign`, `notarytool`, and `stapler validate` results separately from CI. Keep the icon path recorded as omitted until a real `Distribution/macos/icon.png` has passed `iconutil`.

### 2.3 Repair and merge plugin V1

PR #33 must not merge with its current uninstall semantics. The approved spec requires uninstalling a plugin to close its contributed windows.

Implement the following fixed contract:

- Add `SceneConfigurationError.sceneUnavailable(SceneID)`.
- Give contributed scene descriptors an availability closure; `CompiledSceneGraph.scene(id:)` and `makeSurface` must reject a scene after its owning plugin is removed.
- Have `PluginRuntime.uninstall(_:)` collect the plugin's contributed `SceneID`s, remove and deactivate the plugin exactly once, and publish those removed IDs to package-internal scene-lifetime observers.
- Let `PluginScenes` register the runtime's removal source in `_SceneCollector`; carry the source into `CompiledSceneGraph`.
- Have `GamaShellCoordinator` subscribe when created, mark removed scene IDs unavailable, and close every live controller whose `sceneID` was removed through the existing `requestClose` lifecycle.
- Cancel the observer during shell termination/deinitialization.
- Removed slots, commands, and scenes must disappear immediately. Reopening a removed scene must fail without creating an empty window.

Add tests:

- Portable: uninstall removes slots, commands, `contributedSceneIDs`, and surface availability.
- Portable: trying to create a removed surface throws `.sceneUnavailable`.
- AppKit: open a contributed window, uninstall its plugin, assert exactly one close-request/close lifecycle, assert the controller is removed, and assert reopening fails.
- AppKit: uninstalling one plugin leaves another plugin's windows untouched.
- Lifecycle: repeated uninstall is a no-op and never emits duplicate closure events.

Update `docs/Plugins.md` so contributed-window teardown is no longer listed as deferred.

Run:

```bash
unset TOOLCHAINS
swiftly run swift test --scratch-path /private/tmp/gama-framework-swiftpm --filter Plugin
swiftly run swift test --scratch-path /private/tmp/gama-framework-swiftpm --filter PluginSceneShellTests
./scripts/check-apple.sh
./scripts/check-boundaries.sh
./scripts/check-docs.sh
./scripts/check-doc-coverage.sh
```

Commit sequence:

- `fix(plugin): retire contributed scenes on uninstall`
- `test(plugin): prove contributed window teardown`
- `docs(plugin): record uninstall lifecycle guarantees`

Merge only after packaging is already on `main`, PR #33 is updated onto that result, and all six checks are green.

## Task 3: Execute Wave-2 Structural Modernization — Canonical Frame Pump

Capture a release baseline after wave-1 is fully merged and before changing the frame pump. Use a fixed 80×24 render, a 160×48 resize loop, and a deterministic key/pointer sequence. Record median CPU time, p95 frame time, allocation count, and peak memory across five runs.

Implement the approved public surface in `GamaCore`:

```swift
public struct HostPump: ~Copyable {
    public init(host: consuming FrameHost, size: Size)
    public mutating func handle(_ event: InputEvent)
    public mutating func advance<E>(
        emit: (borrowing CellBuffer) throws(E) -> Void
    ) throws(E) -> AdvanceOutcome
    public var needsFrame: Bool { get }
    public var wantsQuit: Bool { get }
    public var size: Size { get }
}

public struct AdvanceOutcome: Sendable {
    public var produced: Bool
    public var followUp: Bool
}
```

Behavior:

- `.resize` eagerly updates size, invalidates, then forwards the event.
- A clean host returns `produced == false` without painting or emitting.
- A dirty host runs exactly one shared `pump → clearBack → paint → emit` sequence.
- `followUp` reports focus-reconciliation dirtiness.
- Buffer ownership remains inside `HostPump`; emitters only borrow it.
- Emission stays backend-specific.

Deliver as separate green PRs:

1. `HostPump` plus portable tests.
2. `AppRuntime`/TUI migration.
3. WASM and C-Embed migration.
4. AppKit/UIKit host and shell migration.
5. ADR 0007 supersession, new final pump ADR, and migration documentation.

Existing WASM and Embed behavioral tests must remain unchanged; that is the compatibility proof. TUI and Apple resize tests change only from lazy to eager timing.

## Task 4: Complete Sendability Redesign and Remaining Slice-C Items

### 4.1 Complete the non-Sendable state redesign

Extend the approved Signal design to cover the declaration layer introduced by plugin V1:

- `Signal` and `PluginRuntime` become explicitly non-Sendable with unavailable `Sendable` conformances.
- `App`, `Scene`, `View`, `State`, and `Binding` lose blanket `Sendable` requirements where their values are executor-confined.
- Binding getter/setter closures lose dishonest `@Sendable` annotations when they can capture a non-Sendable signal.
- Pure transfer values remain Sendable: IDs, geometry, events, `RenderNode`, `DrawList`, window payload values, capability values, and encoded ABI data.
- Entry points that transfer an app/state region into a host use `sending`.
- Re-audit `SubscriptionContext`, `HostActionStore`, plugin callbacks, `CompiledSceneGraph`, and `SceneSurface`; retain `@Sendable` only for closures genuinely crossing an executor boundary.
- No synchronization framework is added to `GamaCore`.

Add `Tests/CompileFail/SignalSendable.swift` and `Tests/CompileFail/PluginRuntimeSendable.swift`, plus `scripts/check-concurrency-negative.sh`. The script must type-check each fixture with the pinned compiler, require compilation to fail, and assert the diagnostic identifies the unavailable Sendable conformance. Add this gate to `check.sh` and CI.

Update ADR 0004 and the Signal design spec with the final declaration-layer consequences.

### 4.2 Finish the remaining Slice-C items as isolated PRs

Land in this order:

1. In-memory `Renderer` test double covering `AppRuntime.run()` begin/frame/event/end and every exit path.
2. Terminal restoration for SIGTERM, SIGHUP, `atexit`, and SIGWINCH, with PTY/process tests.
3. Macro diagnostic Fix-Its, with exact expansion/diagnostic tests.
4. VoiceOver accessibility derived from `currentDrawList`; no parallel application semantics.
5. Scale-aware `ProgressView`.
6. Measure-first optimization of `CellBuffer.presentDiff` and `forEachRun`.
7. `~Copyable` migration for `CellBuffer` and `Terminal`, including deinitialization tests.
8. `StrictMemorySafety` and `InternalImportsByDefault` after boundary scripts recognize the intended imports.
9. MLIR emitter unification with byte-for-byte deterministic fixture tests.

Every item is its own reviewable PR and requires a completed post-merge matrix.

## Task 5: Refactor and Profile the Native Apple Host

Do this after `HostPump` removes duplicated pump machinery; do not perform a generic SwiftUI-style refactor on the current AppKit/UIKit files first.

Split responsibilities:

- `GamaHostView.swift`: platform subclass, installation, frame-request coordination, layout, and public host API.
- `AppleDrawListRenderer.swift`: CoreGraphics replay, color conversion, font selection/cache, and dirty-rect handling.
- `AppleInputTranslator.swift`: AppKit/UIKit key and pointer translation.
- `GamaShell.swift`: public application entry point and menu installation only.
- `GamaShellCoordinator.swift`: scene/window registry, command draining, plugin-scene removal, and application lifecycle.
- `GamaShellWindowController.swift`: native window creation and delegate events.

Preserve behavior and package visibility. Do not add a view model; these are native bridge/controller responsibilities, not SwiftUI screen state.

Performance work is trace-backed:

- Profile the release `gama-apple-demo` with Time Profiler, Allocations, Core Animation, and hangs/hitches.
- Use the same deterministic input/resize scenario captured before `HostPump`.
- Only optimize attributed-string creation, font lookup, DrawList reconstruction, dirty-rect replay, `presentDiff`, or run iteration when the trace identifies them.
- Accept the refactor only when correctness gates remain green and median CPU, allocations, and peak memory are no worse than 5% relative to baseline.
- An optimization claim requires at least a 10% median improvement across five identical release runs or removal of a reproducible hitch.
- Record hypotheses separately from measurements.

For the later SwiftUI adapter, use Apple's SwiftUI Instruments workflow to inspect long body updates and update fan-out. [Apple's current SwiftUI performance guidance](https://developer.apple.com/documentation/Xcode/understanding-and-improving-swiftui-performance) is the profiling authority.

## Task 6: Add the Apple-Family SwiftUI and Liquid Glass Layer

### 6.1 Adopt a separate design and target

Create an approved design spec, then add:

- Library product and target: `GamaSwiftUI`
- Dependencies: `GamaCore`, `GamaAppleUI`
- No dependency from any existing portable target back to `GamaSwiftUI`
- Deployment floors remain macOS 14, iOS 17, tvOS 17, and visionOS 1.
- Native Liquid Glass activates only on macOS/iOS/tvOS/visionOS 26+; earlier systems use material/bordered fallbacks.
- `GamaAppleShell` remains the owner of Gama-native multi-window applications. `GamaSwiftUI` is an opt-in embedding layer for applications whose outer shell is SwiftUI.

### 6.2 Public API

Add these APIs:

```swift
@MainActor
@Observable
public final class GamaSurfaceController {
    public private(set) var isReady: Bool
    public private(set) var installationError: SceneConfigurationError?
    public func invalidate()
}

@MainActor
public struct GamaSurface<Application: GamaCore.App>: SwiftUI.View {
    public init(
        controller: GamaSurfaceController,
        makeApplication: @escaping @MainActor () -> Application
    )
}

@MainActor
public struct GamaGlassWorkspace<Application: GamaCore.App, Controls: SwiftUI.View>: SwiftUI.View {
    public init(
        controller: GamaSurfaceController,
        spacing: CGFloat = 16,
        makeApplication: @escaping @MainActor () -> Application,
        @SwiftUI.ViewBuilder controls: @escaping () -> Controls
    )
}

@MainActor
public struct GamaGlassControlGroup<Content: SwiftUI.View>: SwiftUI.View {
    public init(
        spacing: CGFloat = 12,
        @SwiftUI.ViewBuilder content: @escaping () -> Content
    )
}
```

Implementation contract:

- `GamaSurface` uses `NSViewRepresentable` on macOS and `UIViewRepresentable` on UIKit-family platforms.
- Its coordinator constructs one application/host per SwiftUI identity; ordinary SwiftUI updates must not reinstall the Gama application.
- `GamaSurfaceController` is justified as a bridge object for the non-SwiftUI host. It reports typed installation failure and provides explicit out-of-band invalidation; it contains no application business logic.
- The post-`HostPump` frame-request callback must drive external Gama signal changes without polling or a permanent display link.
- `GamaGlassWorkspace` keeps a stable `ZStack`: the Gama surface is the content plane, while SwiftUI controls are native chrome.
- On OS 26+, group controls inside `GlassEffectContainer`, apply `.glassEffect` after padding/layout modifiers, and use `.buttonStyle(.glass)` or `.glassProminent` only for actual actions.
- The containing glass surface is not marked interactive merely because it contains buttons.
- Use a consistent rounded-rectangle shape with an 18-point radius for workspace chrome.
- On earlier systems, use `.ultraThinMaterial` in the same shape and `.bordered`/`.borderedProminent` buttons.
- Do not add morphing or `glassEffectID` in V1; the hierarchy is intentionally stable.
- Shared application models or explicit closures connect native controls to Gama. The adapter does not inspect or mutate `RenderNode`/`DrawList` to invent a second action system.

### 6.3 Demonstration and documentation

Add:

- `gama-swiftui-demo`, showing a Gama surface with native glass toolbar/status controls.
- `Sources/GamaSwiftUI/GamaSwiftUI.docc/GamaSwiftUI.md`
- `docs/backends/SwiftUI.md`
- README product/example entries.
- A `docs/Capabilities.md` row distinguishing compile proof, automated host proof, OS 26 visual proof, and older-system fallback proof.

Extend `check-apple-platforms.sh` to build both `GamaAppleUI` and `GamaSwiftUI` for iOS, tvOS, and visionOS simulators.

Tests:

- Successful host installation sets `isReady`.
- Invalid scene configuration populates the exact typed error without trapping.
- SwiftUI updates do not reinstall or reset the Gama host.
- Controller invalidation schedules exactly one required frame.
- External Gama signal changes schedule a frame without polling.
- Direct host and SwiftUI wrapper produce identical DrawLists for the same app, size, and input sequence.
- OS-style selection resolves to native glass on 26+ and material fallback below 26.
- Light/Dark Mode, Increase Contrast, Reduce Transparency, keyboard focus, pointer interaction, and VoiceOver receive a manual acceptance pass.
- SwiftUI Instruments show no repeated long body updates and wrapper overhead remains within 5% of direct-host CPU/allocation baseline.

## Task 7: Release, Evidence, and Closeout

After the adapter is green:

- Extend the generic macOS bundling path to accept both `gama-apple-demo` and `gama-swiftui-demo` manifests without duplicating signing logic.
- Produce `Gama SwiftUI Demo.app` under `/private/tmp/gama-dist`, ad-hoc sign it in CI, and run a noninteractive smoke mode.
- Run Developer ID signing, notarization, stapling, and Gatekeeper validation locally with configured credentials.
- Perform real Dock reopen and Command-Q tests for the Gama shell; keep these distinct from offscreen AppKit tests.
- Perform the SwiftUI/Liquid Glass visual and accessibility pass on OS 26+ and one available pre-26 runtime.
- Rebuild all DocC catalogs and verify Pages returns HTTP 200 after deployment.
- Run the complete local matrix:

```bash
cd /Users/donaldfilimon/Desktop/Gama
unset TOOLCHAINS
./scripts/check.sh
```

- Require the six-job PR matrix and completed merge-SHA `main` matrix for every final slice.
- Remove a merged worktree only after it is clean and its branch delta is an ancestor of or patch-equivalent to `main`.
- Keep local preservation branches until the `.gitignore`, `CLAUDE.md`, and `Package.resolved` decisions are visibly accounted for.
- Mark the umbrella goal complete only when wave-1, wave-2, the Apple adapter, documentation, packaging, and required hosted evidence are complete. The absence of a Windows 6.5-dev snapshot remains a documented external blocker, not a reason to overstate Windows evidence.

## Assumptions and Fixed Defaults

- Full roadmap selected, not open-PR-only scope.
- The Apple-family SwiftUI/Liquid Glass layer is required and is opt-in.
- Gama retains ownership of rendering and application semantics.
- Existing deployment floors remain unchanged; availability checks provide older-system fallbacks.
- Packaging precedes plugin merge because plugin PR #33 requires additional lifecycle work.
- ASan retains address-safety coverage with leak detection disabled for the SwiftPM test harness until a narrower, negative-control-proven approach exists.
- `HostPump` lands before native-host file splitting or SwiftUI adaptation.
- Signal/sendability work covers plugin and declaration-layer types added since the original Signal design was written.
- No feature branch merges until governance enforcement and non-cancelled `main` proof are in place.
