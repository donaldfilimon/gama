# Gama umbrella — plugin runtime + capability model (sub-project 2)

Date: 2026-08-27. Status: **approved**. Delivery evidence is maintained in
`docs/Capabilities.md`; approval alone is not an implementation claim.

This specification finalizes the 2026-08-26 draft
(`drafts/2026-08-26-plugin-runtime-draft.md`, kept for rationale and the
rejected-alternatives record). The draft's grounding, tier table, capability
model, testing strategy, and hard constraints carry forward unchanged except
where a decision below amends them. Donald resolved the draft's open
questions on 2026-08-27:

1. **Capability implementations are first-party in this sub-project.** A new
   `GamaPlatformServices` target ships in V1 (decision: "first-party now").
2. **The plugin UI surface is the full contribution surface** — slots,
   scenes/windows, and commands — not slots-only (decision: "full
   contribution surface"). The scene-first shell
   (`2026-08-27-scene-first-app-shell-design.md`, delivered) makes this
   possible without new windowing machinery.
3. Tier-1 enforcement honesty stands as drafted: capability-based design,
   not a sandbox. Tier 2 (dylib) remains Proposed post-V1; Tier 3
   (out-of-process) remains future. No sandbox claim is ever made for
   in-process tiers.

## Amendments to the draft

### A1. `GamaPlatformServices` (new target, V1)

- Platform-conditional target, sibling to the backends: may import
  Foundation/Darwin/Glibc/WinSDK as needed; **never imported by
  `GamaCore`, `GamaPlugin`, `GamaDraw`, or any portable target**
  (`check-boundaries.sh` gains the inverse grep: no portable target may
  import `GamaPlatformServices`).
- Provides ready-made `HostServices` values: `.standard` wires `.log`
  (stderr), `.clock` (monotonic millis), and a real `FilesystemProvider`
  honoring `FilesystemScope` prefixes (exact-match V1 semantics unchanged;
  path containment checked on the resolved absolute path, no symlink
  resolution in V1 — documented limitation).
- On platforms without an OS (wasm32, Embedded) the target is excluded from
  the build graph the same compile-time way `GamaPluginLoader` was sketched:
  portable code never references it, so exclusion is structural.
- `.filesystem` is therefore **real at the end of V1** on macOS/Linux/
  Windows/Android hosts and interface-only where no OS exists — stated in
  `docs/Plugins.md` per the evidence policy.

### A2. Full contribution surface (V1)

The draft's slot mechanism stays (render-IR into app-declared `PluginSlot`s,
`BuildContext.child(i)` identity, host-owned action registration). V1 adds
two host-mediated contribution kinds, both opt-in at the app's scene
declaration, both plain data, no globals:

```swift
// Proposed — target GamaPlugin (stdlib-only; scene types come from GamaCore).
public protocol GamaPluginProtocol: Sendable {
    var manifest: PluginManifest { get }
    mutating func activate(in context: PluginContext) throws(PluginError)
    mutating func deactivate()
    func render(slot: SlotID, in context: BuildContext) -> RenderNode
    /// Scene contributions: additional windows the app agrees to host.
    func scenes(in context: PluginSceneContext) -> [PluginSceneContribution]
    /// Command contributions: named, host-dispatched actions.
    func commands() -> [PluginCommand]
}
```

- `PluginSceneContribution` pairs a `SceneID` (namespaced as
  `plugin/<pluginID>/<name>` to keep the existing `duplicateIDs`-style
  diagnostics collision-free) with a `(BuildContext) -> RenderNode` payload
  and a window role that may never be `.primary` — the app's primary scene
  is not up for grabs. The app opts in by placing `PluginScenes(runtime:)`
  in its `scenes` builder; the shell (`GamaAppleShell`) then treats
  contributed scenes exactly like `Window` declarations, including
  `openWindow`/`dismissWindow` context actions.
- `PluginCommand` is `(CommandID, title, (PluginContext) -> Void)`; the host
  exposes `PluginRuntime.commands` for the app/shell to surface (menu,
  palette, key binding — presentation is the app's choice). Dispatch runs on
  the host's executor like every other action.
- Routes are subsumed by scene contributions in V1 (a route is a scene the
  app names); a dedicated navigation surface waits for a navigation design.

### A3. V1 slice (supersedes draft §4)

In: everything in the draft's V1 list, plus `GamaPlatformServices`
(`HostServices.standard`, real filesystem provider + hostile-path tests),
plus scene and command contributions (types, runtime plumbing,
`PluginScenes`, shell integration test on macOS, portable tests for
identity/dispatch), plus `docs/Plugins.md` and the extended boundary greps.

Out (unchanged): Tier 2 loading, Tier 3 process transport, `.network`
implementation, scope subsumption, manifest macros, discovery/scanning,
plugin-to-plugin dependencies, persistence, C-ABI changes.

### A4. Testing additions (Swift Testing, `Tests/gamaTests`)

Beyond the draft's Slice A/B suites:

- `PluginSceneTests`: contributed scene IDs are namespaced and
  collision-free; a `.primary` contribution is rejected with a typed error;
  `openWindow` on a contributed `SceneID` builds the plugin payload under
  the correct host; uninstall closes contributed windows.
- `PluginCommandTests`: registration order deterministic; dispatch reaches
  the owning plugin's context; a command firing `invalidate()` dirties
  exactly its host.
- `PlatformServicesTests`: filesystem provider refuses paths outside the
  granted prefix (`..`, absolute escapes, empty prefix), exact-match
  semantics pinned; log/clock handles observable via recorders.

Every slice passes the local gates (`check-apple.sh`, `check-boundaries.sh`,
`check-docs.sh`, doc-coverage) and merges only on a green six-job hosted
matrix.
