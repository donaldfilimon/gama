# Gama umbrella — app shell, windowing, lifecycle (sub-project 3) — DRAFT

Date: 2026-08-26. Status: **draft for review** (nothing here is approved;
every new type, target, and symbol below is Proposed unless explicitly
marked as existing code).

Prerequisite reading: `AGENTS.md` (architecture rules),
`docs/superpowers/specs/2026-08-26-gama-umbrella-foundation-design.md`
(locked decisions: own-the-rendering, one `Package.swift`, 6.5-dev main
snapshot), `docs/Capabilities.md` (evidence table).

## 1. Where the shell boundary sits today (grounded survey)

Gama currently renders into a surface someone else creates. The evidence:

- **The engine is already shell-shaped.** `FrameHost<A: App>`
  (`Sources/GamaCore/FrameHost.swift`) is the backend-shared event/focus
  engine: one value per surface, owning focus identity, the action/key
  handler store, dirty state, and an explicit `SubscriptionContext`
  (`FrameHost.swift:40-53`). Its own header comment states the split:
  poll-style renderers wrap it in a blocking `AppRuntime` loop; retained
  hosts call `pump`/`handle` from their own event sources
  (`FrameHost.swift:1-6`). There is no global registry anywhere in
  GamaCore, per the AGENTS.md rule.
- **`App` declares content only.** `public protocol App: Sendable`
  requires `content` and `init()` (`Sources/GamaCore/Runtime.swift:45-49`).
  No windows, no scenes, no lifecycle hooks. `App.main(renderer:)`
  (`Runtime.swift:84`) is the only "run me" entry, and it is TUI-shaped
  (needs a `Renderer`).
- **Who pumps today, per backend:**
  - *TUI*: `AppRuntime.run()` blocks on `renderer.nextEvent(timeoutMillis:)`
    (`Runtime.swift:57-80`); `TUIRenderer` + `RawModeSession`
    (`Sources/GamaTUI/Terminal.swift:31`) own the terminal session. The
    terminal session *is* the window; quit is `wantsQuit`, set by
    Ctrl-C/Ctrl-Q inside `FrameHost.handle` (`FrameHost.swift:136-137`)
    with the comment "hosts may ignore" (`FrameHost.swift:45`).
  - *Apple*: `GamaHostView` (`Sources/GamaAppleUI/GamaHostView.swift`) is
    an NSView/UIView whose `Session<A>` box owns one `FrameHost` + one
    `CellBuffer` (`GamaHostView.swift:120`). AppKit/UIKit's run loop pumps
    it via `layout()`/`draw(_:)`/`keyDown` etc. Nothing creates the
    NSWindow: `Examples/AppleHost/main.swift` builds one by hand, sets
    `window.contentView = GamaHostView(app:)`, and — tellingly — never
    calls `NSApplication.shared.run()`, has no delegate, no menu, no
    termination path. That file is the missing layer, in miniature.
  - *WASM*: reactor style, no blocking loop. `WebHost/gama.js` is the de
    facto shell: it owns the page, instantiates the module, forwards DOM
    events into `gama_web_v1_key/pointer/resize`, and pumps frames through
    `requestAnimationFrame` when the module calls back `requestFrame()`
    (`gama.js:23-30`, `Sources/GamaWASM/WASMHost.swift:90`). The module
    already drives one piece of window chrome: `gama_js_setTitle`
    (`WASMHost.swift:25,82`). Note the deliberate single-instance global
    `_host` (`WASMHost.swift:74`) — a reactor module is one surface by
    construction.
  - *Embed / Android*: the foreign host pumps. `gama_embed_v1_context_create`
    (`Sources/GamaEmbed/CInterface.swift:120`) returns an opaque,
    caller-owned `EmbedContext` (one `FrameHost` per context,
    `CInterface.swift:42`); the C/JNI host calls event + frame entry
    points on its own thread (`Examples/Android/app/src/main/cpp/gama_jni.cpp`,
    `MainActivity.kt`). Gama explicitly does *not* own the loop here, and
    must not — that is the embedding contract.
  - *Windows*: console only (`Terminal.swift` WinSDK branch,
    `Sources/GamaWindowsConsoleSmoke`). There is **no Windows GUI renderer
    at all** — no Win32 window class, no GDI/D2D presenter. A Win32
    message-loop shell has nothing to present into yet.

Conclusion from the survey: the shell is not a new engine — `FrameHost`
already is the engine. The shell is (a) a small portable vocabulary for
lifecycle, and (b) per-platform bootstrap code that creates the surface,
owns the native loop, and translates platform lifecycle into that
vocabulary, exactly as backends already translate input.

## 2. The App protocol surface (Proposed)

Keep `App` as the single application declaration; do not introduce a
parallel "ShellApp" hierarchy. Two additive pieces:

```swift
// GamaCore (stdlib-only, Embedded-safe — plain structs/enums)

public struct ShellConfiguration: Hashable, Sendable {
    public var title: String = "Gama"
    public var initialSize: Size = Size(width: 100, height: 30) // cells
    public var resizable: Bool = true
    public init() {}
}

extension App {
    /// Shell-owned surface preferences. Backends that have no window
    /// (embed) or no chrome (TUI) read what applies and ignore the rest,
    /// mirroring the existing "hosts may ignore" wantsQuit contract.
    public static var shell: ShellConfiguration { ShellConfiguration() }

    /// App-scoped lifecycle observation; default is no-op, so every
    /// existing App (GamaDemo, BrowserDemo, AndroidDemo, CEmbedDiagnosticApp)
    /// compiles unchanged. Nonmutating on purpose: app state lives in
    /// reference-semantics Signals (see AndroidDemoBootstrap.swift:5),
    /// so a nonmutating hook can still update real state.
    public func handleLifecycle(_ event: LifecycleEvent) {}
}
```

What the shell owns, per platform (the app never touches these):

| Platform | Surface created by | Loop pumped by | Shell target |
| --- | --- | --- | --- |
| macOS | `GamaAppleShell` (Proposed): `NSApplication` setup, one `NSWindow`, `GamaHostView` content view, `NSWindowDelegate`/`NSApplicationDelegate` | AppKit run loop (`NSApplication.run()`) | new `GamaAppleShell` target |
| iOS/tvOS/visionOS | `UIApplication` + `UIScene` delegate glue (Proposed, deferred) | UIKit run loop | same target, UIKit branch |
| Windows | Win32 `RegisterClassW`/`CreateWindowW` + `GetMessage` loop — **blocked**: requires a Windows GUI presenter that does not exist (docs/Capabilities.md lists only the console path) | Win32 message loop | deferred |
| WASM | the browser page; `WebHost/gama.js` already is the shell | `requestAnimationFrame` (existing) | extend `gama.js` + `GamaWASM` exports |
| TUI | `RawModeSession` (existing); the terminal session is the window | `AppRuntime.run()` (existing) | `GamaTUI`/`AppRuntime`, additive |
| Embed/JNI | the foreign host — Gama must not own the loop | foreign host | C ABI additive entry point only |

`FrameHost` remains exactly one per surface (today: `AppRuntime`,
`GamaHostView.Session`, `WASMHostBox`, `EmbedContext` each own one). The
shell owns the collection of surfaces; `FrameHost` never learns about
windows. This preserves the AGENTS.md rule "Each `FrameHost` owns focus,
actions, subscriptions, dirty state, and frames" without widening it.

Entry point (macOS V1):

```swift
// GamaAppleShell (Proposed)
@MainActor public enum GamaShell {
    /// Creates NSApplication (.regular activation), one NSWindow sized
    /// from A.shell, installs GamaHostView(app:), wires delegates, runs
    /// the AppKit loop. Never returns (like NSApplicationMain).
    public static func run<A: App>(_ app: A.Type) -> Never
}
```

No process-global Gama registries: the shell instance (an object owned by
the `run` frame and referenced by the delegates) owns the window list and
sessions. `NSApplication` is the platform's own unavoidable singleton; the
rule constrains *Gama* state, and all Gama state stays instance-owned —
the pattern to follow is `GamaHostView.Session` (`GamaHostView.swift:78-120`),
not `GamaWASM._host`.

## 3. Lifecycle: same channel as input (Recommended)

Two candidate designs were considered:

- **A separate lifecycle channel** (a second protocol method on backends,
  a parallel delivery path next to `handle(_:)`).
- **A new `InputEvent` case flowing through the existing
  `FrameHost.handle` funnel.**

**Recommendation: one channel — extend `InputEvent`.**

```swift
// GamaCore/Runtime.swift (Proposed, additive)
public enum LifecycleEvent: Hashable, Sendable {
    case didLaunch
    case willEnterForeground
    case didEnterBackground
    case windowCloseRequested   // red button, browser pagehide, SIGTERM-ish
    case willTerminate
}

public enum InputEvent: Hashable, Sendable {
    case key(Key)
    case resize(Size)
    case pointer(Point, pressed: Bool)
    case tick
    case lifecycle(LifecycleEvent)   // Proposed
}
```

Reasons, in order of weight:

1. **Every backend already has exactly one funnel.** `GamaHostView.handleEvent`
   (`GamaHostView.swift:103`), `WASMHostBox.handle` (`WASMHost.swift:50`),
   `EmbedHostBox.handle` (`CInterface.swift:25`), and `AppRuntime.run()`'s
   loop all deliver `InputEvent` to `FrameHost.handle`. A second channel
   means five backends grow a second pipe, plus new C and WASM ABI surface
   for it — and every future backend must remember to plumb both.
2. **Ordering is free.** Lifecycle interleaves correctly with input by
   construction: `didEnterBackground` arrives after the last key event on
   the same queue that delivered the key. A parallel channel has to
   re-invent that guarantee.
3. **Precedent inside FrameHost.** `resize` is already a quasi-lifecycle
   event living happily in `InputEvent` (`Runtime.swift:19-24`), and quit
   already flows through `handle` (Ctrl-C → `wantsQuit`,
   `FrameHost.swift:136-137`). The channel is not "keyboard events"; it is
   "things that happen to the surface".
4. **Embedded/C safety.** A `Hashable, Sendable` stdlib enum case costs
   nothing; the C ABI stays versioned and additive
   (`gama_embed_v1_lifecycle(ctx, code)` next to the existing
   `gama_embed_v1_key`), and WASM gains `gama_web_v1_lifecycle(code)`
   symmetric with `gama_web_v1_key` (`WASMHost.swift:96`).

Cost acknowledged: adding a case is source-breaking for any external
exhaustive `switch` over `InputEvent`. In-repo, `FrameHost.handle` ends in
`default: break` and backends use `if case .resize` patterns
(`CInterface.swift:26`, `WASMHost.swift:56`), so nothing in-tree breaks;
Gama is pre-1.0 and the umbrella spec already accepts deliberate breaks.

In `FrameHost.handle` (Proposed):

```swift
case .lifecycle(let event):
    if event == .windowCloseRequested || event == .willTerminate {
        wantsQuit = true            // unifies with the existing Ctrl-C path
    }
    app.handleLifecycle(event)      // no-op unless the app opts in
    dirty.set(true)
```

This makes Ctrl-C and the red close button converge on the same
`wantsQuit` semantics the TUI already honors, and lets the AppKit shell
read `host.wantsQuit` after each delivery to drive `NSApp.terminate`.
V1 has **no veto** (no `windowShouldClose`-style cancel); see open
question 1.

Per-platform mapping (Proposed):

- macOS: `applicationDidFinishLaunching` → `.didLaunch`;
  `windowWillClose`/close button → `.windowCloseRequested`;
  `applicationWillTerminate` → `.willTerminate`; app hide/unhide →
  background/foreground.
- WASM: module install → `.didLaunch`; `visibilitychange` →
  foreground/background; `pagehide` → `.windowCloseRequested` (delivered
  best-effort; browsers do not guarantee it).
- TUI: `AppRuntime.run()` emits `.didLaunch` before the first frame and
  `.willTerminate` after the loop exits, before `renderer.end()`. Keeps
  the "portable enum" claim honest on a second platform in V1.
- Embed: the foreign host calls the new C entry point when it pleases;
  Gama imposes no ordering beyond "after context_create".

## 4. Multi-window: minimum viable model (Proposed, mostly deferred)

Facts constraining the design: TUI, WASM, and Embed are single-surface by
nature (one terminal, one reactor `_host`, one context per… well, embed
already supports N contexts — `EmbedTests.swift` proves "contexts own
independent frames"). `FrameHost` is cheap and value-typed; N windows is
N hosts, which the embed ABI has effectively already demonstrated.

V1 model:

1. **The App declares one primary surface** (`App.shell`). That is the
   whole declarative surface in V1 — no `WindowGroup`, no scene builder.
2. **`FrameHost` is strictly per-window.** A second window is a second
   `FrameHost` over the same app *type* (or a different content closure —
   deferred), created and owned by the shell. State sharing between
   windows happens the way it already does between any two hosts: shared
   `Signal`s observed via each host's `SubscriptionContext`
   (`State.swift:18-47`), which was explicitly designed so "destroying or
   resetting one host cannot leave observers that invalidate a different
   host".
3. **Imperative capability, optional by construction.** Degradation for
   single-surface backends is handled by making window operations
   *capabilities the environment may not carry*, not protocol
   requirements:

   ```swift
   // GamaCore EnvironmentValues (Proposed), next to focusedID (View.swift:46)
   public struct ShellCapabilities: Sendable {
       public var setTitle: (@Sendable (String) -> Void)? = nil
       public var requestClose: (@Sendable () -> Void)? = nil
       public var openWindow: (@Sendable () -> Void)? = nil  // V2, see below
   }
   ```

   AppKit fills all three; WASM fills `setTitle` (the JS import already
   exists, `WASMHost.swift:25`); TUI fills `requestClose` (sets
   `wantsQuit`) and maybe `setTitle` (OSC 2 escape — deferred); Embed
   fills none. A `nil` capability is the graceful degrade: the app can
   feature-detect, and code written against it still compiles and runs
   everywhere. This is the same shape as the existing `wantsQuit` "hosts
   may ignore" contract, made explicit.
4. **Deferred to V2 (not designed here):** window groups/scene syntax,
   per-window `LifecycleEvent` addressing (V1 lifecycle is app-scoped; with
   one window they coincide), window placement/restoration, and
   `openWindow`'s payload story. Sub-project 2 (plugin runtime) should
   weigh in first, since plugins are a likely `openWindow` consumer.

What V1 deliberately does *not* do: make `FrameHost` window-aware, add a
window ID to `InputEvent`, or grow `App` with an associated Scene type.
Each of those is real cost today for a capability nothing in the repo
needs yet.

## 5. V1 slice (Proposed): macOS shell + portable lifecycle spine

Justification for macOS-first, from the evidence table
(`docs/Capabilities.md`) and code:

- The Mac AppKit host is the only retained-GUI backend that is *locally
  runtime proven* (host instantiation, layout, invalidation, draw-list
  production). iOS is compile-proven only; Windows GUI has no renderer at
  all; WASM already has a working de facto shell (`gama.js`), so a shell
  there is polish, not a missing layer.
- `Examples/AppleHost/main.swift` is the smoking gun: today a Mac
  developer must hand-roll `NSWindow`, gets no event loop, no menu, no
  termination, no lifecycle. That is precisely the Tauri-class gap.
- Local gates (`scripts/check-apple.sh`) run on this machine; a macOS
  shell is provable end-to-end today without waiting on hosted Windows
  jobs, which the Capabilities table lists as the blocked column.

V1 contents (in order; all Proposed):

1. **GamaCore additive spine:** `LifecycleEvent`, `InputEvent.lifecycle`,
   `App.handleLifecycle` default, `ShellConfiguration` + `App.shell`,
   `ShellCapabilities` in `EnvironmentValues`, `FrameHost.handle` case.
   Stdlib-only; Embedded gate (`scripts/check-embedded.sh`) must stay
   green — these are plain enums/structs/closures, nothing else.
2. **`GamaAppleShell` target** (new library target, macOS branch only in
   V1): `GamaShell.run(_:)` creating `NSApplication` (activation policy
   `.regular`), one `NSWindow` from `App.shell` (title, size sized in
   cells × the host's cell metrics, resizable mask), `GamaHostView`
   content, delegates translating AppKit lifecycle → `.lifecycle(...)`
   events into the view's existing `handleEvent` funnel, quit when
   `wantsQuit` or last window closes, and a minimal main menu (app menu
   with Quit ⌘Q) so the result behaves like a real .app. Kept separate
   from `GamaAppleUI` so the embed-into-your-own-window contract
   (`window.contentView = GamaHostView(app:)`) survives untouched.
3. **TUI emission:** `AppRuntime.run()` emits `.didLaunch` /
   `.willTerminate` (two lines each side of the existing loop,
   `Runtime.swift:66-79`).
4. **Example:** rewrite `Examples/AppleHost/main.swift` to
   `GamaShell.run(AppleExample.self)` — the before/after is the sales
   pitch.
5. **Explicitly out of V1:** iOS `UIScene` glue, Windows Win32 shell
   (blocked on a nonexistent Windows GUI presenter *and* the hosted
   Windows job), WASM lifecycle exports (cheap, but do it when a consumer
   exists), C ABI lifecycle entry point (same), multi-window, veto/cancel
   on close, state restoration, dock/menu customization.

## 6. Testing strategy (Proposed)

All tests use Swift Testing (`import Testing`) in `Tests/gamaTests`.
There is no XCTest suite. New suites follow `docs/Testing.md`.

1. **Portable spine tests (pure, no platform, run everywhere):**
   - `FrameHost.handle(.lifecycle(...))`: `.windowCloseRequested` sets
     `wantsQuit`; `.didEnterBackground` does not; handler receives events
     in delivery order; a handler mutating a `Signal` marks the host dirty.
     Pattern: the existing `FrameHostTests` drive `handle` directly.
   - `AppRuntime` lifecycle emission: a scripted in-memory `Renderer`
     (`Failure == Never`, feeding a fixed event list — same shape the
     existing runtime tests use) records that the app saw
     `.didLaunch` before the first `present` and `.willTerminate` after
     the loop, exactly once each.
   - `ShellCapabilities` degrade: a view reading a `nil` `openWindow`
     renders the fallback branch (compile + behavior check).
2. **AppleShell behavioral tests (macOS, `#if canImport(AppKit)`,
   `@MainActor`):** the existing `AppleHostTests.swift` proves the
   pattern — instantiate real AppKit objects without ever calling
   `NSApp.run()`. Extend it:
   - Build the shell's window controller/delegate directly; invoke
     `windowWillClose(_:)` / `applicationWillTerminate(_:)` by hand and
     assert the app's recorded lifecycle sequence and `wantsQuit`.
   - Assert window title and size derive from `App.shell`.
   - Assert `GamaHostView` is the content view and first responder wiring
     still holds (`GamaHostView.swift:160-162` behavior, now shell-owned).
   This directly addresses the current gap: AppleUI has compile gates and
   one runtime smoke, but almost no behavioral coverage. Delegate-methods-
   called-directly is the honest level available without a windowserver
   session; anything needing a real `NSApp.run()` stays a supplemental
   manual smoke, as the TUI's interactive smoke already is
   (`docs/Capabilities.md`, Mac POSIX TUI row).
3. **Gates:** everything above runs under the existing
   `scripts/check-apple.sh` and portable suites; `scripts/check-embedded.sh`
   proves the GamaCore additions stay Embedded-safe; no new gate is
   introduced. Per AGENTS.md, no cross-platform gate is weakened, and the
   Capabilities table gains a row ("macOS app shell") only with local
   runtime evidence, marked blocked-for-hosted like its peers.

## 7. Open questions for Donald

1. **Close-request veto:** V1 hardwires `windowCloseRequested → wantsQuit`
   (no cancel). Do you want a `windowShouldClose`-style veto (app returns
   Bool / calls a `cancelClose` capability) in V1, or is unsaved-state
   protection a V2 concern? V1-as-drafted says V2.
2. **Ctrl-C ownership:** should `FrameHost` keep the hardwired
   Ctrl-C/Ctrl-Q → quit (`FrameHost.swift:136`), or should it synthesize
   `.lifecycle(.windowCloseRequested)` so apps observe *every* quit path
   through one hook? The synthesis is cleaner but changes long-standing
   TUI behavior surface; drafted as: keep the hardwire, additionally
   forward a synthesized lifecycle event.
3. **Multi-window declaration timing:** the imperative `openWindow`
   capability is deliberately stubbed (`nil` everywhere) in V1. Should
   sub-project 2 (plugin runtime) be specified against it — plugins
   opening tool windows — or should windows stay app-only until a
   declarative scene syntax exists? This decides whether `openWindow`
   needs a payload/content parameter now or can wait.

## 8. Non-goals restated

No webview, no native-widget mapping (locked by the foundation spec). No
Windows GUI work until a presenter exists. No change to the embed
contract: foreign hosts keep owning their loops. No process-global Gama
state anywhere in the shell. GamaCore stays stdlib-only and
Embedded-safe; every shell dependency on AppKit lives in the new target.
