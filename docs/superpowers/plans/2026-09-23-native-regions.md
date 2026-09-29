# Native Regions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a Gama app reserve a laid-out, focusable *native region* with a portable fallback, and let the Apple host fill it with an app-owned `NSView`/`UIView`.

**Architecture:** A region is the existing `RenderNode.interactive` node around a flexible fallback. It registers `(NodeID, NativeRegionID)` with its host through a new `BuildContext` hook, exactly as `Button` registers actions. `FrameHost` joins that table with the `interactive` frames after focus reconciliation and publishes `nativeRegions`. `GamaHostView` places attached views on those frames. `RenderNode`, `LayoutEngine`, `CellPainter`, MLIR, TUI, WASM, Embed and the DrawList wire format are unchanged.

**Tech Stack:** Swift 6.5-dev snapshot (`main-snapshot-2026-08-21`), SwiftPM, Swift Testing, AppKit/UIKit.

**Spec:** `docs/superpowers/specs/2026-09-23-native-region-design.md` (on PR #107). Policy: ADR 0016.

## Context

Donald approved the native-region spec (PR #107, branch `docs/native-surface-draft`, head `bfb19dd`) and asked for this plan. Reading the code while planning turned up **three corrections to the spec**. Task 0 applies them before any code:
1. `GamaPlatformView` is already a public typealias (`NSView`/`UIView`, `Sources/GamaAppleUI/GamaHostView.swift`), so `attach` is declared **once** as `attach(_ view: GamaPlatformView, to:)`. The spec's "no `PlatformView` typealias" is wrong.
2. An `interactive` wrapper passes through its child's flexibility, so a small fallback like `Text("3D")` would make a small region. `NativeRegion` therefore renders its fallback inside `.frame(maxWidth: .max, maxHeight: .max)`, which makes it flexible on both axes as the spec intends.
3. `HTMLSerializer` is internal to `GamaWASM`. Fallback parity is proved at the painted `CellBuffer` and `DrawListSerializer` level. Every serializer (TUI, HTML, DrawList) consumes that same buffer, so the buffer is the parity point.

## Global Constraints

- **Toolchain:** the pin comes from `.swift-version` (`main-snapshot-2026-08-21`). Run `unset TOOLCHAINS` first. The manifest stays `swift-tools-version: 6.4`.
- **Where work happens:** in a `/private/tmp/gama-native-regions` worktree, never in the iCloud checkout (another session's uncommitted files live there). It must stay outside iCloud because `swift test` fails at codesign inside it.
- **Portable targets stay standard-library-only:** `GamaCore` gains no imports.
- **Every new public symbol gets a `///` doc comment**, because the doc-coverage gate requires it. No allowlist entries.
- **Swift Testing only.** `#expect` on a `~Copyable` host property needs binding to a local first.
- **Filters and scratch:** `--filter` matches the struct name, and a filter that matches nothing exits 0, so always read the test count. Give each gate its own scratch path (`GAMA_APPLE_SCRATCH_PATH=/private/tmp/gama-nr-apple`, `GAMA_SCRATCH_ROOT=/private/tmp/gama-nr`).
- **Naming:** "native region". Never "surface" or "slot".
- **No `docs/Capabilities.md` row** in this plan (see "Deliberately not in this plan").

---

### Task 0: Branch, worktree, and spec corrections

**Files:** Modify `docs/superpowers/specs/2026-09-23-native-region-design.md`; Create `docs/superpowers/plans/2026-09-23-native-regions.md` (this plan, verbatim).

- [ ] **Step 1:** Create the worktree and branch:
  `cd ~/Desktop/Gama && git fetch origin && git worktree add -b feat/native-regions /private/tmp/gama-native-regions origin/docs/native-surface-draft`
- [ ] **Step 2:** In the spec's `GamaAppleUI` block:
  - Replace the two-platform `attach(_ view: NSView…)` sketch and the paragraph "There is no `PlatformView` typealias…" with `public func attach(_ view: GamaPlatformView, to id: NativeRegionID)`, plus one sentence: "`GamaPlatformView` is the existing public alias for `NSView`/`UIView`."
  - In the data-flow and API text, state that `NativeRegion` renders `fallback.frame(maxWidth: .max, maxHeight: .max)` inside the `interactive` node.
  - In Testing, replace "through the TUI cell buffer, `DrawListSerializer`, and `HTMLSerializer`" with "in the painted `CellBuffer` and its `DrawListSerializer` output, which every serializer consumes".
- [ ] **Step 3:** Save this plan to `docs/superpowers/plans/2026-09-23-native-regions.md`.
- [ ] **Step 4:** Run the doc checkers:
  `for c in check-doc-links evidence-locality referenced-paths; do python3 "scripts/$c.py" --self-test . >/dev/null; echo "$c: $?"; done`
  Expect `0` for all three.
- [ ] **Step 5:** Commit: `docs(specs): correct native region spec against the code; add plan`.

### Task 1: `NativeRegionID`, `NativeRegion`, and the `BuildContext` hook

**Files:**
- Create: `Sources/GamaCore/NativeRegion.swift`
- Modify: `Sources/GamaCore/View.swift` (`BuildContext`)
- Test: `Tests/gamaTests/NativeRegionTests.swift`

**Interfaces:**
- Produces:
  - `NativeRegionID(_ rawValue: String)` (`Hashable, Sendable`, `rawValue: String`)
  - `NativeRegion<Fallback: View>(_ id: NativeRegionID, focusable: Bool = true, @ViewBuilder fallback: () -> Fallback)`
  - `BuildContext.registerNativeRegion: (NodeID, NativeRegionID) -> Void`, with a matching trailing `init` parameter defaulting to `{ _, _ in }`

- [ ] **Step 1: Write the failing tests** (`Tests/gamaTests/NativeRegionTests.swift`):

```swift
//  NativeRegionTests.swift — native regions (ADR 0016): build, host table, fallback parity.

import GamaCore
import GamaDraw
import GamaMLIR
import Testing

private let viewport = NativeRegionID("viewport")

/// Records registrations; a class so the escaping hook can append.
private final class RegionLog { var entries: [(NodeID, NativeRegionID)] = [] }

@Suite("Native region build")
struct NativeRegionBuildTests {
    @Test("host-less render is the interactive node around a flexible fallback")
    func hostlessRender() {
        let region = NativeRegion(viewport) { Text("3D") }
        let expected = RenderNode.interactive(
            id: .root, focusable: true,
            child: Text("3D").frame(maxWidth: .max, maxHeight: .max).render(in: BuildContext().child(0)))
        #expect(region.render(in: BuildContext()) == expected)
    }

    @Test("the hook receives the node id and region id")
    func hookReceivesRegistration() {
        let log = RegionLog()
        let context = BuildContext(registerNativeRegion: { log.entries.append(($0, $1)) })
        _ = NativeRegion(viewport) { Text("3D") }.render(in: context)
        #expect(log.entries.count == 1)
        #expect(log.entries.first?.0 == .root)
        #expect(log.entries.first?.1 == viewport)
    }

    @Test("focusable: false and a disabled environment stay out of focus order")
    func focusableFlags() {
        let off = NativeRegion(viewport, focusable: false) { Text("3D") }.render(in: BuildContext())
        guard case .interactive(_, let focusable, _) = off else { Issue.record("not interactive"); return }
        #expect(focusable == false)
        var env = EnvironmentValues(); env.isEnabled = false
        let disabled = NativeRegion(viewport) { Text("3D") }.render(in: BuildContext(environment: env))
        guard case .interactive(_, let disabledFocusable, _) = disabled else { Issue.record("not interactive"); return }
        #expect(disabledFocusable == false)
    }

    @Test("the fallback paints exactly like the same tree without registration")
    func fallbackPaintParity() {
        let size = Size(width: 20, height: 4)
        let regionNode = NativeRegion(viewport) { Text("3D viewport") }.render(in: BuildContext())
        let plainNode = RenderNode.interactive(
            id: .root, focusable: true,
            child: Text("3D viewport").frame(maxWidth: .max, maxHeight: .max).render(in: BuildContext().child(0)))
        func painted(_ node: RenderNode) -> DrawList {
            var buffer = CellBuffer(size: size)
            CellPainter.paint(LayoutEngine.layout(node, in: Rect(origin: .zero, size: size)), into: &buffer)
            return DrawListSerializer().serialize(buffer)
        }
        #expect(painted(regionNode) == painted(plainNode))
        #expect(painted(regionNode).commands.contains { if case .text(let s, _, _) = $0 { s.contains("3D viewport") } else { false } })
    }

    @Test("MLIR sees no new op: a region lowers exactly as its interactive node")
    func mlirUnchanged() {
        let regionNode = NativeRegion(viewport) { Text("3D") }.render(in: BuildContext())
        let plainNode = RenderNode.interactive(
            id: .root, focusable: true,
            child: Text("3D").frame(maxWidth: .max, maxHeight: .max).render(in: BuildContext().child(0)))
        #expect(GamaLowering.lower(module: regionNode) == GamaLowering.lower(module: plainNode))
    }
}
```

- [ ] **Step 2:** Run `unset TOOLCHAINS; swiftly run swift test --scratch-path /private/tmp/gama-nr-swiftpm --filter NativeRegionBuildTests`. Expect a compile failure: `cannot find 'NativeRegionID' in scope`.
  - If `EnvironmentValues.isEnabled` is not settable or `CellBuffer(size:)` differs, read `View.swift` and `CellBuffer.swift` and adjust the **test** to the real spelling. Don't change the library for the test.
- [ ] **Step 3: Add the hook to `BuildContext`** (`Sources/GamaCore/View.swift`):
  - Insert this stored property after `registerNamedAction`:

```swift
    /// Registers a native region (ADR 0016) with the owning host, pairing the
    /// region's interactive node with the application's region identity. The
    /// default is a no-op, so a host-less build renders the fallback and
    /// reports no regions.
    public var registerNativeRegion: (NodeID, NativeRegionID) -> Void
```

  - Add the trailing init parameter `registerNativeRegion: @escaping (NodeID, NativeRegionID) -> Void = { _, _ in }` after `registerNamedAction`, and assign it with `self.registerNativeRegion = registerNativeRegion`. `child(_:)` copies `self`, so the hook is inherited with no further change.
- [ ] **Step 4: Create `Sources/GamaCore/NativeRegion.swift`:**

```swift
//  NativeRegion.swift — GamaCore
//  A laid-out region an opting-in presentation host may fill with an
//  application-owned view (ADR 0016). Every backend paints the fallback;
//  the region is an ordinary interactive node, registered with the host the
//  way Button registers its action.

/// Application-chosen identity for a native region. Equal tokens name the
/// same region; a host attaches views by this identity.
public struct NativeRegionID: Hashable, Sendable {
    /// Application-supplied token.
    public var rawValue: String

    /// Creates an identity from `rawValue`.
    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

/// Reserves a laid-out, focusable region that a presentation host may fill
/// with an application-owned platform view.
///
/// Compiles to `RenderNode.interactive` around `fallback`, stretched to fill
/// the space the region is given, so every backend lays it out, focuses it,
/// hit-tests it, and paints the fallback. A host that attaches a view to
/// ``NativeRegionID`` shows that view instead, inside the region only.
public struct NativeRegion<Fallback: View>: View {
    /// A primitive: compiles directly through ``render(in:)``.
    public typealias Body = Never_
    /// Never invoked; present only to satisfy `View`.
    public var body: Never_ { Never_() }

    /// The identity a host attaches a view to.
    public var id: NativeRegionID
    /// Whether the region takes keyboard focus; a disabled environment
    /// always removes it from focus order.
    public var focusable: Bool
    /// Painted on every backend, and wherever no view is attached.
    public var fallback: Fallback

    /// Creates a region identified by `id` with a portable `fallback`.
    public init(_ id: NativeRegionID, focusable: Bool = true, @ViewBuilder fallback: () -> Fallback) {
        self.id = id
        self.focusable = focusable
        self.fallback = fallback()
    }

    /// Registers the region with the owning host and compiles to a
    /// focusable `.interactive` node around the stretched fallback.
    public func render(in context: BuildContext) -> RenderNode {
        context.registerNativeRegion(context.id, id)
        return .interactive(
            id: context.id,
            focusable: focusable && context.environment.isEnabled,
            child: fallback.frame(maxWidth: .max, maxHeight: .max).render(in: context.child(0))
        )
    }
}
```

- [ ] **Step 5:** Run the Step 2 command. Expect `5 tests … passed`. Read the count.
- [ ] **Step 6:** Commit: `feat(core): NativeRegion and the BuildContext registration hook`.

### Task 2: `FrameHost` region table, `nativeRegions`, and `HostPump` forwarding

**Files:**
- Modify: `Sources/GamaCore/FrameHost.swift`, `Sources/GamaCore/HostPump.swift`, `Sources/GamaCore/NativeRegion.swift` (add `NativeRegionFrame`)
- Test: `Tests/gamaTests/NativeRegionTests.swift` (new suite)

**Interfaces:**
- Consumes: `BuildContext.registerNativeRegion` from Task 1.
- Produces:
  - `NativeRegionFrame(id: NativeRegionID, node: NodeID, frame: Rect, isFocused: Bool)`, `Hashable, Sendable`, with a public init
  - `FrameHost.nativeRegions: [NativeRegionFrame]`
  - `FrameHost.duplicateNativeRegionIDs: [NativeRegionID]`
  - `HostPump.nativeRegions`
  - `HostPump.duplicateNativeRegionIDs`

- [ ] **Step 1: Write the failing tests.** Append to `NativeRegionTests.swift`:

```swift
private struct RegionApp: App {
    let show = Signal(true)
    var scenes: some Scene {
        Window("Regions", id: "main", role: .primary) {
            VStack {
                Button("Top") {}
                if show.get() {
                    NativeRegion(viewport) { Text("3D") }.frame(width: 20, height: 5)
                }
            }
        }
    }
}

private struct DuplicateApp: App {
    var scenes: some Scene {
        Window("Dup", id: "main", role: .primary) {
            VStack {
                NativeRegion(viewport) { Text("A") }.frame(width: 10, height: 2)
                NativeRegion(viewport) { Text("B") }.frame(width: 10, height: 2)
            }
        }
    }
}

@Suite("Native region host table")
struct NativeRegionHostTests {
    private let size = Size(width: 40, height: 10)

    @Test("a registered region is published with its laid-out frame")
    func publishedWithFrame() throws {
        var host = try FrameHost(app: RegionApp())
        _ = host.pump(size: size)
        let regions = host.nativeRegions
        #expect(regions.count == 1)
        #expect(regions.first?.id == viewport)
        #expect(regions.first?.frame.size == Size(width: 20, height: 5))
        #expect((regions.first?.frame.minY ?? 0) >= 1)  // below the button
    }

    @Test("a region absent after a rebuild disappears")
    func disappearsAfterRebuild() throws {
        let app = RegionApp()
        var host = try FrameHost(app: app)
        _ = host.pump(size: size)
        app.show.set(false)
        _ = host.pump(size: size)
        let regions = host.nativeRegions
        #expect(regions.isEmpty)
    }

    @Test("isFocused follows host focus")
    func focusTracks() throws {
        var host = try FrameHost(app: RegionApp())
        _ = host.pump(size: size)            // focus lands on the first focusable, the button
        let before = host.nativeRegions
        #expect(before.first?.isFocused == false)
        host.handle(.key(.tab))
        _ = host.pump(size: size)
        let after = host.nativeRegions
        #expect(after.first?.isFocused == true)
    }

    @Test("a duplicate id is reported and the last registration wins")
    func duplicatesReported() throws {
        var host = try FrameHost(app: DuplicateApp())
        _ = host.pump(size: size)
        let regions = host.nativeRegions
        let duplicates = host.duplicateNativeRegionIDs
        #expect(regions.count == 1)
        #expect(duplicates == [viewport])
        #expect((regions.first?.frame.minY ?? 0) >= 2)  // the second, lower region
    }

    @Test("HostPump forwards the host's regions")
    func pumpForwards() throws {
        var pump = HostPump(host: try FrameHost(app: RegionApp()), size: size)
        _ = pump.advance()
        let regions = pump.nativeRegions
        #expect(regions.map(\.id) == [viewport])
    }
}
```

- [ ] **Step 2:** Run `--filter NativeRegionHostTests` and expect the build to fail on `nativeRegions`.
  - If `VStack` doesn't accept `if` in its builder, replace the conditional with `NativeRegion(...).frame(width: show.get() ? 20 : 0, height: show.get() ? 5 : 0)`, and in the rebuild test assert that `frame.size == .zero` instead. Only the fallback's shape in the test changes.
- [ ] **Step 3: Add `NativeRegionFrame`** to `NativeRegion.swift`:

```swift
/// One native region of a laid-out frame, as a host consumes it: which
/// region, which interactive node carries it, where it is in cells, and
/// whether host focus is on it.
public struct NativeRegionFrame: Hashable, Sendable {
    /// The application's identity for the region.
    public let id: NativeRegionID
    /// The interactive node that carries the region.
    public let node: NodeID
    /// The region's absolute frame in grid cells.
    public let frame: Rect
    /// Whether host focus is on ``node`` in this frame.
    public let isFocused: Bool

    /// Creates a region record.
    public init(id: NativeRegionID, node: NodeID, frame: Rect, isFocused: Bool) {
        self.id = id
        self.node = node
        self.frame = frame
        self.isFocused = isFocused
    }
}
```

- [ ] **Step 4: Extend the host.** In `FrameHost.swift`:
  - In `HostActionStore`:
    - add `var regions: [NodeID: NativeRegionID] = [:]`;
    - add `regions.removeAll(keepingCapacity: true)` to `beginBuildPass()`;
    - add `func registerRegion(_ id: NodeID, _ region: NativeRegionID) { regions[id] = region }` and `func region(for id: NodeID) -> NativeRegionID? { regions[id] }`.
  - In `FrameHost`, after `transientStateIDs`:

```swift
    /// Native regions (ADR 0016) in the most recent frame, in visual order,
    /// with focus already reconciled. A presentation host places attached
    /// views on these frames; every other backend ignores them.
    public private(set) var nativeRegions: [NativeRegionFrame] = []
    /// Native region identities registered more than once in the most
    /// recent frame. The last registration wins in ``nativeRegions``.
    public private(set) var duplicateNativeRegionIDs: [NativeRegionID] = []
```

  - In `buildFrame`, pass `registerNativeRegion: { id, region in actionStore.registerRegion(id, region) }` to the `BuildContext` init.
  - In `pump(size:)`, call `publishNativeRegions()` immediately before `return laid`, after focus reconciliation, so `isFocused` reflects the final focus.
  - Add:

```swift
    /// Joins the latest build's region registrations with its interactive
    /// frames. Keeps the last registration of a repeated identity, at its
    /// own visual position, and records the identity as a duplicate.
    private mutating func publishNativeRegions() {
        let all: [NativeRegionFrame] = interactive.compactMap { item in
            actions.region(for: item.id).map {
                NativeRegionFrame(id: $0, node: item.id, frame: item.frame, isFocused: item.id == focusedID)
            }
        }
        var seen: Set<NativeRegionID> = []
        var kept: [NativeRegionFrame] = []
        for entry in all.reversed() where seen.insert(entry.id).inserted {
            kept.append(entry)
        }
        nativeRegions = kept.reversed()
        var counted: [NativeRegionID: Int] = [:]
        for entry in all { counted[entry.id, default: 0] += 1 }
        var reported: Set<NativeRegionID> = []
        duplicateNativeRegionIDs = all.compactMap { entry in
            (counted[entry.id, default: 0] > 1 && reported.insert(entry.id).inserted) ? entry.id : nil
        }
    }
```

  - In `HostPump.swift`, after `wantsQuit`:

```swift
    /// The host's native regions for the most recent frame (ADR 0016).
    public var nativeRegions: [NativeRegionFrame] { host.nativeRegions }
    /// Native region identities the most recent frame registered more than once.
    public var duplicateNativeRegionIDs: [NativeRegionID] { host.duplicateNativeRegionIDs }
```

- [ ] **Step 5:** Run `--filter NativeRegionHostTests` (expect 5 passed), then `--filter NativeRegion` (expect 10), reading the counts.
- [ ] **Step 6:** Run `./scripts/check-boundaries.sh` with `GAMA_SCRATCH_ROOT=/private/tmp/gama-nr`. Expect `OK` (GamaCore imports nothing new).
- [ ] **Step 7:** Commit: `feat(core): FrameHost publishes native regions with reconciled focus`.

### Task 3: Apple host: attach, placement, no overdraw, focus handoff, accessibility

**Files:**
- Modify: `Sources/GamaAppleUI/GamaHostView.swift`, `Sources/GamaAppleUI/GamaHostAccessibility.swift`
- Test: `Tests/gamaTests/AppleHostNativeRegionTests.swift` (AppKit, `#if canImport(AppKit)` like `AppleHostAccessibilityTests.swift`)

**Interfaces:**
- Consumes: `HostPump.nativeRegions` and `NativeRegionFrame` from Task 2.
- Produces:
  - `GamaHostView.attach(_ view: GamaPlatformView, to id: NativeRegionID)`
  - `GamaHostView.detach(_ id: NativeRegionID)`
  - `package func isCoveredByNativeRegion(_ cells: Rect) -> Bool`, for the no-overdraw test

- [ ] **Step 1: Write the failing tests.** Mirror the `installedView()` pattern from `AppleHostAccessibilityTests.swift`:

```swift
#if canImport(AppKit)
    import AppKit
    import GamaAppleUI
    import GamaCore
    import Testing

    @Suite("AppKit host native regions")
    @MainActor
    struct AppleHostNativeRegionTests {
        private struct ViewportApp: App {
            let show = Signal(true)
            var scenes: some Scene {
                Window("Studio", id: "main", role: .primary) {
                    VStack {
                        Button("Panel") {}
                        NativeRegion(NativeRegionID("viewport")) { Text("3D viewport") }
                            .frame(width: show.get() ? 20 : 0, height: show.get() ? 5 : 0)
                    }
                }
            }
        }

        private func installed(_ app: ViewportApp) throws -> GamaHostView {
            let view = GamaHostView(frame: NSRect(x: 0, y: 0, width: 420, height: 240))
            try view.install(app: app)
            view.layoutSubtreeIfNeeded()
            view.invalidate()
            return view
        }

        @Test("an attached view is placed on the region's frame and shown")
        func placedAndShown() throws {
            let host = try installed(ViewportApp())
            let native = NSView()
            host.attach(native, to: NativeRegionID("viewport"))
            #expect(native.superview === host)
            #expect(native.isHidden == false)
            #expect(native.frame.width > 0 && native.frame.height > 0)
            #expect(host.isCoveredByNativeRegion(Rect(origin: Point(x: Int(native.frame.minX / host.cellSize.width), y: Int(native.frame.minY / host.cellSize.height)), size: Size(width: 1, height: 1))))
        }

        @Test("the view hides when its region goes away and stays attached")
        func hidesWhenAbsent() throws {
            let app = ViewportApp()
            let host = try installed(app)
            let native = NSView()
            host.attach(native, to: NativeRegionID("viewport"))
            app.show.set(false)
            host.invalidate()
            #expect(native.isHidden == true)
            #expect(native.superview === host)
        }

        @Test("re-attaching replaces the view and detach removes it")
        func replaceAndDetach() throws {
            let host = try installed(ViewportApp())
            let first = NSView(), second = NSView()
            host.attach(first, to: NativeRegionID("viewport"))
            host.attach(second, to: NativeRegionID("viewport"))
            #expect(first.superview == nil)
            #expect(second.superview === host)
            host.detach(NativeRegionID("viewport"))
            #expect(second.superview == nil)
        }

        @Test("Gama focus on the region makes the attached view first responder")
        func focusHandoff() throws {
            let host = try installed(ViewportApp())
            let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: true)
            window.contentView = host
            let native = FocusableView()
            host.attach(native, to: NativeRegionID("viewport"))
            host.send(.key(.tab))   // button → region
            #expect(window.firstResponder === native)
            host.send(.key(.tab))   // region → button: host reclaims
            #expect(window.firstResponder === host)
        }

        @Test("an attached view is an accessibility child between the rows")
        func accessibilityChild() throws {
            let host = try installed(ViewportApp())
            let native = NSView()
            host.attach(native, to: NativeRegionID("viewport"))
            let children = host.accessibilityChildren() ?? []
            #expect(children.contains { ($0 as AnyObject) === native })
        }

        private final class FocusableView: NSView {
            override var acceptsFirstResponder: Bool { true }
        }
    }
#endif
```

  - `cellSize` and `send(_:)` must be visible to tests. `send` is `package` already. If `cellSize` is private, make it `package` (read-only) rather than duplicating its math.
- [ ] **Step 2:** Run `--filter AppleHostNativeRegionTests` and expect a compile failure on `attach`.
- [ ] **Step 3: Host state and API.** In `GamaHostView.swift`:
  - Add the stored state next to the accessibility cache:

```swift
    // MARK: Native regions (ADR 0016)
    /// Application-owned views attached to native regions, by identity.
    var attachedNativeViews: [NativeRegionID: GamaPlatformView] = [:]
    /// Regions of the most recent frame, kept so attach/detach can place a
    /// view without waiting for the next frame.
    private var lastNativeRegions: [NativeRegionFrame] = []
    /// Cell frames of regions currently showing an attached view; drawing
    /// skips commands wholly inside them.
    private var shownNativeRegionCells: [Rect] = []
    /// Regions whose attached view was given first responder last frame.
    private var focusedNativeRegions: Set<NativeRegionID> = []
```

  - Add a public API section:

```swift
    /// Attaches an application-owned view to the native region `id`. The
    /// application keeps ownership; the host adds it as a subview, places it
    /// on the region's frame each frame, hides it while the region is absent,
    /// and hands it first responder when Gama focus lands on the region.
    /// Attaching a different view to the same identity detaches the first.
    public func attach(_ view: GamaPlatformView, to id: NativeRegionID) {
        if let previous = attachedNativeViews[id], previous !== view {
            previous.removeFromSuperview()
        }
        attachedNativeViews[id] = view
        if view.superview !== self { addSubview(view) }
        view.isHidden = true
        placeNativeRegions(lastNativeRegions)
    }

    /// Removes the view attached to `id`, if any, from this host.
    public func detach(_ id: NativeRegionID) {
        attachedNativeViews.removeValue(forKey: id)?.removeFromSuperview()
        placeNativeRegions(lastNativeRegions)
    }

    /// Whether `cells` lies wholly inside a region currently showing an
    /// attached view. Package-only so the no-overdraw rule is testable.
    package func isCoveredByNativeRegion(_ cells: Rect) -> Bool {
        shownNativeRegionCells.contains { region in
            cells.minX >= region.minX && cells.minY >= region.minY
                && cells.maxX <= region.maxX && cells.maxY <= region.maxY
        }
    }

    private func placeNativeRegions(_ regions: [NativeRegionFrame]) {
        lastNativeRegions = regions
        var byID: [NativeRegionID: NativeRegionFrame] = [:]
        for region in regions { byID[region.id] = region }
        var shown: [Rect] = []
        var focused: Set<NativeRegionID> = []
        for (id, view) in attachedNativeViews {
            guard let region = byID[id] else {
                view.isHidden = true
                continue
            }
            view.frame = pixelRect(region.frame)
            view.isHidden = false
            shown.append(region.frame)
            if region.isFocused {
                focused.insert(id)
                if !focusedNativeRegions.contains(id) { giveFirstResponder(to: view) }
            }
        }
        if !focusedNativeRegions.subtracting(focused).isEmpty { giveFirstResponder(to: self) }
        focusedNativeRegions = focused
        if shown != shownNativeRegionCells {
            shownNativeRegionCells = shown
            setNeedsDisplayCompat()
        }
    }

    private func giveFirstResponder(to view: GamaPlatformView) {
        #if canImport(AppKit)
            _ = unsafe window?.makeFirstResponder(view)
        #else
            _ = view.becomeFirstResponder()
        #endif
    }
```

  - In `install(surface:)`'s `driver` closure, after `guard outcome.produced else { return }`, add `self.placeNativeRegions(session.pump.nativeRegions)`.
  - `tearDown()` leaves attached views alone. The app owns them, and `detach` is the removal path.
- [ ] **Step 4: No overdraw.** In `draw(_:)`:
  - Before the `.fillRect` fill, add `if isCoveredByNativeRegion(r) { continue }`.
  - Before building the text attributes, add `if isCoveredByNativeRegion(Rect(origin: p, size: Size(width: s.count, height: 1))) { continue }`.
- [ ] **Step 5: Accessibility.** In `GamaHostAccessibility.swift`, add:

```swift
        /// Line elements and shown attached native views, in top-to-bottom
        /// order, so VoiceOver reaches a native view between the rows around it.
        func accessibilityChildrenInReadingOrder() -> [Any] {
            let lines: [(row: Int, element: Any)] = accessibilityLineElements().map { ($0.line.row, $0) }
            let views: [(row: Int, element: Any)] = attachedNativeViews.values
                .filter { !$0.isHidden }
                .map { (Int($0.frame.minY / max(accessibilityCellSize.height, 1)), $0) }
            return (lines + views).sorted { $0.row < $1.row }.map(\.element)
        }
```

  - In `GamaHostView.swift`, return `accessibilityChildrenInReadingOrder()` from `accessibilityChildren()` (AppKit) and from `accessibilityElements` (UIKit), instead of `accessibilityLineElements()`.
  - First confirm the row property's real name on `AccessibilitySnapshot`'s line type and on `GamaAccessibilityLineElement`. Use it, not the guessed `line.row`.
- [ ] **Step 6:** Run `--filter AppleHostNativeRegionTests` (expect 5 passed), then `--filter AppleHostAccessibilityTests` (the existing tests must still pass; `children.count == lines.count` holds because no view is attached there).
  - If `NSWindow` first-responder handoff can't be observed headless under `swift test`, keep the other four tests. Replace the focus test with a check on a package-visible `focusedNativeRegions` count, and record the gap in the report. Never delete the assertion silently.
- [ ] **Step 7:** Commit: `feat(apple): attach app-owned views to native regions`.

### Task 4: Gates, docs, and the stacked PR

**Files:**
- Modify: `docs/Testing.md` (table rows for `NativeRegionTests.swift` and `AppleHostNativeRegionTests.swift`)
- Modify: `CLAUDE.md` (the "decided but not built" sentence)
- Modify: the spec's status paragraph

- [ ] **Step 1:** Add the two rows to the `docs/Testing.md` table, in the file-name order the table already uses:
  - ``| `NativeRegionTests.swift` | Native region build, host table — filter `NativeRegionBuildTests`, `NativeRegionHostTests` |``
  - ``| `AppleHostNativeRegionTests.swift` | AppKit host native regions |``
- [ ] **Step 2:** Update the status and bookkeeping text:
  - Spec status: "Implemented on branch `feat/native-regions`; locally gated on macOS only; no hosted run (billing lock)."
  - `CLAUDE.md`: replace "Native regions are decided but not built … No target, node, or host API exists yet, and the implementation design must settle the open questions…" with "Native regions exist (ADR 0016; design `docs/superpowers/specs/2026-09-23-native-region-design.md`): `NativeRegion` is an `interactive` node registered like an action, and `GamaHostView.attach(_:to:)` fills it on Apple. Tab out of a native view, overlays, sub-cell placement, and Embed/WASM publication are still open."
- [ ] **Step 3:** Run the gates, each with its own scratch path, capturing exit codes from the command itself. None of these may regress:
  - `GAMA_APPLE_SCRATCH_PATH=/private/tmp/gama-nr-apple ./scripts/check-apple.sh`
  - `./scripts/check-apple-platforms.sh` (UIKit compile for `attach`)
  - `GAMA_SCRATCH_ROOT=/private/tmp/gama-nr ./scripts/check-boundaries.sh`
  - `GAMA_CONCURRENCY_NEGATIVE_SCRATCH_PATH=/private/tmp/gama-nr-neg ./scripts/check-concurrency-negative.sh`
  - `./scripts/check-mlir.sh`. This one hardcodes `/private/tmp/gama-framework-swiftpm`, so run it when no peer gate is active.
  - `GAMA_DOCC_SCRATCH_PATH=/private/tmp/gama-nr-docc ./scripts/check-docs.sh`
  - `./scripts/check-doc-coverage.sh`
  - `./scripts/check-package-graph.sh`
- [ ] **Step 4:** Re-read `git diff origin/docs/native-surface-draft` as a reviewer. Confirm:
  - no platform import landed in GamaCore;
  - every new public symbol has a `///` comment;
  - no `RenderNode` case was added.
- [ ] **Step 5:** Commit the docs, push `feat/native-regions`, and open a PR **based on `docs/native-surface-draft`** (stacked on #107). The body lists each gate's local result and says the hosted checks are blocked by billing. Then remove the worktree after confirming the push, keeping the branch until merge.

## Deliberately not in this plan (spec "does not decide")

- Tab out of a native view that consumes Tab (question 2).
- Overlays above a region (3).
- Sub-cell placement (4).
- Embed/WASM publication (5).
- A runtime test on iOS or visionOS (7): only the compile is covered, by `check-apple-platforms`.
- No `docs/Capabilities.md` row: gate 14 needs an evidence anchor, and hosted evidence is blocked. A "locally proven" row may be proposed in the report, not added silently.

## Verification (end to end)

- Every gate in Task 4 Step 3 exits 0, read from its own exit code and verdict line.
- The new suites report 10 core tests plus 5 AppKit tests (counts read from the log), and the existing `AppleHostAccessibilityTests` still pass.
- Two mutation checks, each restored and verified by grep:
  - drop `publishNativeRegions()` from `pump` and confirm `NativeRegionHostTests` fails;
  - drop the `placeNativeRegions` call from `driver` and confirm `AppleHostNativeRegionTests` fails.
- Manual smoke, optional and reported as not run if skipped: a tiny macOS demo attaching a colored `NSView` to a region in `gama-apple-demo` is out of scope, so say so rather than claim visual proof.
