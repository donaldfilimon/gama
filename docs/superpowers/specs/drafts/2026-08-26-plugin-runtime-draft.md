# Gama umbrella — plugin runtime + capability model (sub-project 2) — DRAFT

Date: 2026-08-26. Status: **draft for review — every design element below is
Proposed unless explicitly marked as existing code.** Nothing here is
implemented; no file in the repository changes with this document.

Grounding: written against the actual sources — `Sources/GamaCore/FrameHost.swift`,
`Runtime.swift`, `State.swift`, `View.swift`, `RenderNode.swift`,
`Sources/GamaEmbed/CInterface.swift`, `Sources/GamaEmbedABI/include/GamaEmbed.h`,
`Sources/GamaWASM/WASMHost.swift`, `Sources/GamaMacros/Macros.swift`,
`Package.swift`, `AGENTS.md`, `docs/Capabilities.md`,
`docs/superpowers/specs/2026-08-26-gama-umbrella-foundation-design.md`, and
`scripts/check-boundaries.sh`.

Hard constraints honored throughout (from `AGENTS.md` and the foundation spec):

- `GamaCore` stays stdlib-only, Embedded-Swift-safe, no global mutable
  registries; each `FrameHost` owns focus/actions/subscriptions/dirty state
  (`FrameHost.swift:24`, enforced by `scripts/check-boundaries.sh`).
- Zero runtime dependencies (`Package.swift` documents swift-syntax as
  build-time only).
- wasm32 and Embedded cannot `dlopen`; Windows is a first-class target family.

---

## 1. What is a "plugin" for Gama at runtime?

Four distinct things could claim the word. The design names them as tiers and
commits to different amounts of each:

| Tier | Name | Linkage | Isolation | Platforms | Status |
| --- | --- | --- | --- | --- | --- |
| 0 | Compile-time macro plugin | Runs in the host compiler, never linked | n/a (build host) | all | **Exists** (`GamaMacrosImpl`, `Sources/GamaMacros/Macros.swift`) |
| 1 | Statically-registered feature module | Compiled into the app | None (same address space) — capability model is cooperative | **all**, including wasm32/Embedded/Windows | **Proposed — the V1 baseline** |
| 2 | Dynamically-loaded host plugin | `dlopen` / `LoadLibraryW` of a versioned C entry point | None (same address space) | macOS/Linux/Windows/Android only — structurally impossible on wasm32/Embedded | Proposed, post-V1, optional platform capability |
| 3 | Out-of-process plugin over the C ABI | Separate process/component; versioned message ABI | **Real** (process boundary) | wherever processes exist | Proposed, future; the only tier where capabilities are enforced, not promised |

Definitional stance (Proposed): **a Gama runtime plugin is a unit that (a)
carries a static manifest — identity, version, ABI number, required and
optional capabilities; (b) receives everything it may touch through a
`PluginContext` handed to it at activation — never fetched from a global; (c)
contributes host-mediated services and/or render-IR; (d) has a lifecycle owned
by the same object that owns the `FrameHost` it extends.** Tier 0 is
deliberately excluded from the runtime model: `Macros.swift` already states
"nothing here costs anything at runtime", and that property must survive this
sub-project.

Why the IR is the plugin UI boundary: `View.swift` is "fully generic — user
code never touches `any View`" (Embedded-safe, no existentials in hot paths),
so plugins cannot portably hand the host a `some View`. But `RenderNode`
(`RenderNode.swift:30`) is a pure `Sendable` value enum — the framework's own
erasure boundary. **Plugins contribute `(BuildContext) -> RenderNode`
closures, not views.** The same boundary already carries the whole UI across
the C ABI in `GamaEmbed` (DrawList out), so this is the established pattern,
one level higher.

Tier 3 is the `GamaEmbed` contract with the roles inverted. Today
`gama_embed_v1_*` (`CInterface.swift:120`, `GamaEmbed.h`) lets a foreign host
drive a Gama app: events in, DrawList bytes out, opaque per-context ownership,
versioned symbols. An out-of-process plugin is the mirror image: the Gama app
is the host, the plugin is the foreign component, and the same disciplines
(versioned flat C ABI, single-render-thread rule, explicit context lifetime,
length-prefixed byte frames) carry over. That symmetry is why Tier 3 is
credible later without being built now.

## 2. Capability model

### 2.1 Declaration

The manifest is **code, not a JSON file**. Gama has no runtime file loading in
its portable core (stdlib-only, no Foundation), and a Swift value is
typo-checked by the compiler where a JSON manifest is typo-checked in
production. Conceptually this is Tauri's `capabilities/*.json` +
permission identifiers collapsed into one typed value:

```swift
// All Proposed. Lives in a NEW stdlib-only target `GamaPlugin`
// (depends only on GamaCore; same strictCore settings; subject to the
// same check-boundaries.sh greps — Proposed gate extension).

public struct PluginID: Hashable, Sendable, ExpressibleByStringLiteral {
    public var raw: String            // reverse-DNS, e.g. "dev.gama.stats"
}

public struct PluginVersion: Hashable, Sendable {
    public var major: Int, minor: Int, patch: Int   // no Foundation semver
}

public enum Capability: Hashable, Sendable {
    case log                              // host-mediated logging
    case clock                            // monotonic time from the host
    case filesystem(FilesystemScope)      // scoped, not ambient
    case network(NetworkScope)            // reserved: interface defined later
    // Closed enum ON PURPOSE for V1: adding a capability is a framework
    // decision with a review, not a plugin-author string.
}

public enum FilesystemScope: Hashable, Sendable {
    case read(pathPrefix: String)
    case readWrite(pathPrefix: String)
}

public struct PluginManifest: Sendable {
    public var id: PluginID
    public var version: PluginVersion
    public var abi: UInt32                // gamaPluginABI == 1
    public var requires: [Capability]     // all-or-nothing at install
    public var optional: [Capability]     // granted subset appears in context
}
```

### 2.2 Grant/deny

Grants are **data, not a callback** — inspectable, testable, serializable by
an app shell later. Deny-by-default:

```swift
public struct CapabilityGrants: Sendable {
    public static let denyAll: CapabilityGrants
    public var table: [PluginID: Set<Capability>]
    public func permits(_ id: PluginID, _ capability: Capability) -> Bool
}
```

V1 matching is **exact-match only**. Scope subsumption (a grant of
`.filesystem(.read("/a"))` satisfying a request for `/a/b`) is a real feature
with real path-normalization traps (`..`, symlinks, Windows separators, case
sensitivity) — explicitly deferred, and the doc/test suite must say
"exact-match" out loud so nobody assumes prefix semantics silently.

Install semantics: every `manifest.requires` entry must be permitted or
`install` fails with a typed error naming the first missing capability
(mirrors the typed-throws discipline of `Runtime.swift`). `optional` entries
are filtered: the granted subset determines which handles the context exposes.

### 2.3 What "enforcement" honestly means, per tier

This is where a Tauri copy would lie. Tauri's permissions are enforceable
because the untrusted code sits behind a webview/IPC boundary and physically
cannot reach the OS except through `invoke`. Gama Tier 1 plugins are **Swift
code linked into the process**: nothing a library does can stop them from
importing Foundation and opening a file themselves. The design therefore
claims exactly this, no more:

- **Tier 1 (static): capability-based design, not a sandbox.** The host hands
  a plugin only the handles it granted; handles are unforgeable outside the
  `GamaPlugin` module (internal initializers), and there is no ambient
  `Gama.filesystem` global to steal — consistent with the framework's
  no-global-registries rule. The model governs *host-mediated authority* and
  produces an auditable manifest; it does not confine a malicious plugin.
  Value delivered: least-privilege by construction for cooperating code,
  reviewable grants, and a manifest that is already the right shape for the
  tiers where enforcement is real.
- **Tier 2 (dylib): same trust story as Tier 1** plus a signature/ABI check at
  load. Loading code is the trust decision; the manifest is metadata.
- **Tier 3 (out-of-process): the SAME manifest becomes actually enforceable.**
  The plugin process can only act through the message ABI; the host executes
  granted requests and refuses the rest. This is the Tauri analogy done
  Gama's way: the trust boundary is the C ABI/process boundary, not a
  webview.
- **Platform layers do the rest for free.** A wasm32 plugin cannot call the
  OS at all — the host controls every import (see `WASMHost.swift`'s
  `@_extern(wasm, module: "gama", ...)` imports: the JS side decides what
  exists). Embedded has no OS. macOS App Sandbox/entitlements can back Tier 3
  helpers. The manifest is the single declaration that each platform enforces
  as strongly as it physically can.

### 2.4 Capability implementations

`GamaCore`/`GamaPlugin` stay stdlib-only, so they define capability
*interfaces* only. Implementations are supplied by whoever owns the host —
the application today, the app-shell target (sub-project 3) later:

```swift
public struct HostServices: Sendable {           // Proposed
    public var log: (@Sendable (PluginID, String) -> Void)?
    public var clock: (@Sendable () -> UInt64)?  // monotonic millis
    public var filesystem: FilesystemProvider?   // app/shell-supplied
    public init(...)                             // public: the app IS the host
}
```

This preserves the zero-runtime-dependency property structurally: the portable
targets never import Foundation to make `.filesystem` work; a platform that
can't provide a service simply doesn't, and the corresponding grants fail
closed at install.

## 3. Registration and discovery API (portable baseline)

### 3.1 The plugin protocol

```swift
// Proposed — target GamaPlugin, stdlib-only.

public protocol GamaPluginProtocol: Sendable {
    var manifest: PluginManifest { get }
    /// Called once at install, on the host's executor. Everything the
    /// plugin may touch arrives here; keep what you need.
    mutating func activate(in context: PluginContext) throws(PluginError)
    mutating func deactivate()
    /// Optional render-IR contribution for a named slot the app renders.
    func render(slot: SlotID, in context: BuildContext) -> RenderNode
}

extension GamaPluginProtocol {
    public mutating func deactivate() {}
    public func render(slot: SlotID, in context: BuildContext) -> RenderNode { .empty }
}

public struct SlotID: Hashable, Sendable, ExpressibleByStringLiteral { ... }

public enum PluginError: Error, Hashable, Sendable {
    case duplicate(PluginID)
    case abiMismatch(expected: UInt32, found: UInt32)
    case missingRequiredCapability(PluginID, Capability)
    case activationFailed(PluginID)
}
```

### 3.2 The per-host runtime — ownership without globals

The model is `SubscriptionContext` (`State.swift:18`): a final class owned by
one host, confined to that host's executor, cancelling everything it owns on
`deinit`. `PluginRuntime` is its sibling:

```swift
// Proposed.
public final class PluginRuntime: @unchecked Sendable {   // executor-confined,
    public init(                                          // like FrameHost itself
        grants: CapabilityGrants,
        services: HostServices,
        subscriptions: SubscriptionContext   // THE HOST'S context — FrameHost.swift:43
    )
    public func install(_ plugin: some GamaPluginProtocol) throws(PluginError)
    public func uninstall(_ id: PluginID)                 // deactivates, releases
    public private(set) var installed: [PluginID]         // deterministic order
    /// Render every installed plugin's contribution for one slot.
    public func render(slot: SlotID, in context: BuildContext) -> RenderNode
    deinit  // deactivates all — mirrors SubscriptionContext.deinit
}

public struct PluginContext: Sendable {
    public let plugin: PluginID
    /// nil unless the matching capability was granted. Handles have
    /// internal inits: unforgeable outside GamaPlugin.
    public let log: LogAccess?
    public let clock: ClockAccess?
    public let filesystem: FilesystemAccess?    // scoped to the granted prefix
    /// Host invalidation + signal observation, bounded by THIS host's
    /// lifetime. Wired to FrameHost.subscriptions — a plugin Signal change
    /// dirties exactly one host.
    public let subscriptions: SubscriptionContext
    public func invalidate()
}
```

Threading through `FrameHost` — **`FrameHost` itself does not change in V1.**
It already exposes everything needed: `subscriptions` (`FrameHost.swift:43`)
for invalidation/observation, and `BuildContext` (`View.swift:7`) for build-time
registration of actions and key handlers. Wiring:

```swift
// Application code. Explicit, per-host, no globals anywhere:
var host = FrameHost(app: MyApp())        // note: constructed directly; the
                                          // App.main(renderer:) convenience
                                          // stays plugin-free
let plugins = PluginRuntime(
    grants: myGrants,
    services: HostServices(log: { id, line in ... }),
    subscriptions: host.subscriptions
)
try plugins.install(StatsPlugin())

// Inside the app's content, the app OPTS IN to a slot:
struct MyApp: App {
    ...
    var content: some View {
        VStack {
            Header()
            PluginSlot("sidebar", runtime: plugins)   // a plain View
            Footer()
        }
    }
}
```

`PluginSlot` is an ordinary primitive view whose `render(in:)` calls
`runtime.render(slot:in:)`, expanding each plugin under
`context.child(i)` exactly as `TupleView` numbers its children
(`View.swift:35`) — so plugin-contributed interactive nodes get stable,
collision-free `NodeID`s from the existing FNV path derivation
(`RenderNode.swift:19`) and the existing `duplicateIDs` diagnostic in
`FrameHost` keeps working with no new identity machinery. Interactions inside
plugin IR register through the slot's `BuildContext.registerAction` /
`registerKeyHandler`, i.e. into the owning host's `HostActionStore`, again
with zero new mechanism.

Two hosts, two runtimes: nothing is shared, which is the same isolation
property the concurrent-host tests already prove for the core
(`docs/Capabilities.md` "concurrent host isolation").

Discovery: **there is none in V1, deliberately.** Static registration — an
explicit `install` list in application code — is the only portable mechanism
(wasm32/Embedded cannot enumerate or load anything at runtime), and it is also
how Tauri itself registers Rust plugins (`.plugin(...)` on the builder).
Proposed post-V1 sugar, still no globals: a `@PluginEntry`-style macro
(Tier 0) that synthesizes manifest boilerplate, and — for Tier 2 platforms
only — directory scanning done by the app shell, feeding the same `install`
call. Note the WASM backend's file-private `_host` global
(`WASMHost.swift:74`) is a reactor-model necessity scoped to that backend and
explicitly not a precedent for the plugin layer; `check-boundaries.sh` greps
against exactly this pattern spreading into GamaCore/GamaEmbed.

### 3.3 Tier 2 sketch (Proposed, post-V1, not in V1)

A separate target (working name `GamaPluginLoader`) that exists only for
`os(macOS) || os(Linux) || os(Windows) || os(Android)` — the portable targets
never reference it, so wasm32/Embedded exclusion is a compile-time fact rather
than a runtime check. The dylib exports a versioned flat entry point in the
`gama_embed_v1_*` naming tradition:

```c
/* Proposed. Mirrors GamaEmbed.h conventions: versioned symbols,
   opaque contexts, caller-owned lifetime, 0/-1/-2 result codes. */
int32_t gama_plugin_v1_manifest(uint8_t *out, int32_t capacity);  /* encoded manifest */
void   *gama_plugin_v1_create(void *host_context);
void    gama_plugin_v1_destroy(void *plugin);
```

The loader `dlopen`s / `LoadLibraryW`s, reads the manifest, and then feeds a
thin adapter into the SAME `PluginRuntime.install` path — grants, context,
lifecycle identical to Tier 1. Loading a dylib is a trust decision; the
manifest gate still runs so a loaded plugin cannot silently hold more
host-mediated authority than a static one.

### 3.4 Tier 3 sketch (Proposed, future)

Out-of-process plugin = a worker process speaking a length-prefixed message
ABI: manifest exchange, capability-scoped requests (host executes or refuses
against the same `CapabilityGrants`), and optionally DrawList-encoded UI
frames for a slot — the `DrawList.encode()` bytes that already cross the
`gama_embed_v1_frame` boundary today. No design work is spent here now beyond
reserving the property that made it cheap: the manifest and grants types are
already plain data, and the UI boundary is already bytes.

## 4. V1 slice — the smallest verified thing

**In (all Proposed):**

1. New stdlib-only target `GamaPlugin` (deps: `GamaCore` only), added to the
   `GamaTests` target's dependencies. strictCore settings.
2. Types: `PluginID`, `PluginVersion`, `PluginManifest`, `Capability`
   (exactly `.log`, `.clock`, `.filesystem(FilesystemScope)` — enough to
   prove unscoped vs scoped), `CapabilityGrants` (exact-match, deny-by-default),
   `PluginError`, `HostServices`, `PluginContext` + the three handle types,
   `SlotID`, `GamaPluginProtocol`, `PluginRuntime`, `PluginSlot`.
3. One demo plugin wired into `GamaDemo` behind the existing demo (a status
   line contributed via a slot, using `.log` + `.clock`) — the vertical slice
   that proves the API is usable, not just testable.
4. `check-boundaries.sh` extended to hold `GamaPlugin` to the GamaCore greps
   (stdlib-only, no process-global state). Docs: a short
   `docs/Plugins.md` stating the tier table and the Tier-1 enforcement
   honesty paragraph, and a `docs/Capabilities.md` row once local evidence
   exists — following the repo's implemented/locally-proven/blocked labeling
   rule from `AGENTS.md`.

**Out (explicitly deferred):** dynamic loading (Tier 2), out-of-process
(Tier 3), `.network` implementation, scope subsumption/path normalization,
manifest macros, discovery/scanning, plugin-to-plugin dependencies, plugin
settings/persistence, versioned inter-plugin services, and any change to
`FrameHost`, `App`, `AppRuntime`, or the C ABI. Windows needs nothing special
in V1: `GamaPlugin` is stdlib-only and compiles wherever `GamaCore` does.

Rationale: the manifest/grant/handle machinery is the part every later tier
reuses verbatim, and it is fully verifiable with pure in-memory tests on the
default platform — no new CI jobs, no platform gates, no blocked claims.

## 5. Testing strategy (swift-testing, `Tests/gamaTests`)

Following house style: `@Suite`/`@Test` with behavior-named cases
(`EmbedTests.swift`), hostile-input coverage, and per-host isolation proofs.
Run through the existing gates only (`./scripts/check-apple.sh` etc.);
remember this checkout's iCloud rule — tests execute via the check scripts or
`--scratch-path` outside iCloud, never bare `swift test` in place.

**Slice A — manifest/grants/lifecycle (`PluginRuntimeTests.swift`):**

- deny-by-default: install with `.denyAll` and a nonempty `requires` fails
  with `missingRequiredCapability` naming the right capability; nothing is
  activated (observable via a probe plugin recording lifecycle calls).
- all-or-nothing: one missing required capability out of three ⇒ no partial
  activation, runtime state unchanged, second install attempt after fixing
  grants succeeds.
- optional filtering: granted-optional handle non-nil, ungranted-optional
  handle nil; required handles always non-nil after successful install.
- exact-match scoping: grant `.filesystem(.read("/a"))` does NOT satisfy
  `.filesystem(.read("/a/b"))` — the deliberate V1 semantics pinned by test.
- duplicates: same `PluginID` twice ⇒ `.duplicate`; `abi` ≠ 1 ⇒
  `.abiMismatch`.
- ownership: two `PluginRuntime`s with distinct `HostServices` recorders —
  a plugin in one never reaches the other's services; dropping a runtime
  deactivates its plugins (deinit test, mirroring `SubscriptionContext`).
- invalidation: plugin calls `context.invalidate()` ⇒ exactly its own host's
  `needsFrame` flips true (build two `FrameHost`s, assert the other stays
  clean — same shape as the existing concurrent-host isolation tests).

**Slice B — render contribution (`PluginSlotTests.swift`):**

- a slot with zero plugins renders `.empty` and adds no interactive nodes.
- contributed IR appears in `pump(size:)` output at the slot's position;
  a contributed `.interactive` node's action registers in the owning host
  (drive `handle(.pointer(...))` through the public API and observe the
  plugin's Signal change, exactly how `FormControlTests` drive controls).
- identity stability: two plugins in one slot get distinct `NodeID`s;
  reinstalling in the same order reproduces the same IDs; `duplicateIDs`
  stays empty.
- a plugin Signal observed via `context.subscriptions` dirties the host and
  the next pump shows the new value (end-to-end reactive path).

**Slice A/B macro-free by design** — no changes near `GamaMacrosImpl`, so
`MacroExpansionTests` are untouched.

**Slice C (Tier 2, when built):** fixture dylib compiled by a new
`scripts/check-plugin-loader.sh` into a scratch path outside iCloud; tests
skip (not fail) when the fixture env var is absent, the same
conditional-evidence pattern the Android/Windows gates use. Malformed-library
cases: missing symbol, bad ABI version, truncated manifest ⇒ typed errors,
no crash — hostile-input discipline matching the DrawList codec tests.

**Slice D (Tier 3, when built):** a pure-C consumer harness alongside
`scripts/check-c-abi.sh`, driving manifest exchange and a refused
capability request over the wire.

## 6. Open questions for Donald

1. **Who ships capability implementations?** V1 makes them app-supplied
   (zero-dep preserved absolutely). Long-term: does an optional first-party
   `GamaPlatformServices` target (Foundation/platform APIs, never imported by
   portable targets) belong to sub-project 2 or to the app shell
   (sub-project 3)? This decides whether `.filesystem` is real or interface-only
   at the end of V1.
2. **Is Tier-1 honesty enough for the Tauri-class story?** In-process
   capabilities are auditable least-privilege, not confinement. If marketing
   "sandboxed plugins" matters, Tier 3 moves from "future" to "the point",
   and its message ABI deserves design time now rather than later.
3. **Plugin UI surface: slots only?** V1 says plugins render only into
   app-declared `PluginSlot`s. Full contribution (routes, windows, commands)
   needs the app shell. Confirm slots-only is acceptable for V1, and whether
   Tier 2 (dylibs) is wanted at all — static + out-of-process may cover every
   real use, and Tauri itself ships static-only plugin linkage.

Secondary (decide any time before Tier 2): grant persistence format for the
app shell, scope-subsumption semantics and path normalization, plugin
inter-dependency ordering, and whether `PluginRuntime.install` should be
callable after the first pump (V1 can require install-before-first-frame and
lift it later).
