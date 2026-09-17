# Plugins and the capability model

Status: Tier 1 (static plugins) is implemented and hosted proven. The original
integration and the follow-up that repaired lifecycle, identity, command
revocation, observation ownership, and lexical-path defects each passed their
exact-head six-job acceptance matrix before merging. Tiers 2 and 3 are
Proposed and not implemented. See
[Capabilities.md](Capabilities.md#status-vocabulary) for the vocabulary.

Design authority:
`superpowers/specs/2026-08-27-plugin-runtime-design.md` (approved), with
rationale in `superpowers/specs/drafts/2026-08-26-plugin-runtime-draft.md`.

## Tiers

| Tier | Name | Linkage | Isolation | Platforms | Status |
| --- | --- | --- | --- | --- | --- |
| 0 | Compile-time macro plugin | Runs in the host compiler, never linked | n/a (build host) | all | Exists (`GamaMacrosImpl`); deliberately outside the runtime model |
| 1 | Statically-registered feature module | Compiled into the app | None (same address space); capability model is cooperative | all, including wasm32/Embedded/Windows | Implemented (this V1) |
| 2 | Dynamically-loaded host plugin | `dlopen` / `LoadLibraryW` of a versioned C entry point | None (same address space) | macOS/Linux/Windows/Android only | Proposed, post-V1 |
| 3 | Out-of-process plugin over the C ABI | Separate process; versioned message ABI | Real (process boundary) | wherever processes exist | Proposed, future; the only tier where capabilities are enforced, not promised |

## What "enforcement" honestly means

**Tier 1 is capability-based design, not a sandbox, and no sandbox claim
is ever made for in-process tiers.** A Tier-1 plugin is Swift code linked
into the process: nothing a library does can stop it from importing
Foundation and opening a file itself. What the model does claim, exactly
and no more: the host hands a plugin only the handles it granted; handles
are unforgeable outside the `GamaPlugin` module (internal initializers);
and there is no ambient `Gama.filesystem` global to steal, consistent
with the framework's no-global-registries rule. The model governs
host-mediated authority and produces an auditable manifest; it does not
confine a malicious plugin. The value is least-privilege by construction
for cooperating code, reviewable grants, and a manifest already the right
shape for the tiers where enforcement is real: Tier 2 adds a load-time
trust decision over the same story, and Tier 3 makes the same manifest
actually enforceable because the plugin process can only act through the
message ABI. Platform layers do the rest for free (a wasm32 plugin cannot
call the OS at all; Embedded has no OS).

## The model in five types

- `PluginManifest` declares identity (`PluginID`), `PluginVersion`, the
  ABI number (`PluginManifest.currentABI == 1`), required capabilities,
  and optional capabilities. Manifests are code, not JSON.
- `Capability` is a closed enum: `.log`, `.clock`,
  `.filesystem(FilesystemScope)`. Adding a capability is a framework
  decision with a review.
- `CapabilityGrants` is a deny-by-default data table. **Matching is
  exact-match only in V1**: a grant of `.filesystem(.read("/a"))` does
  not satisfy a request for `.filesystem(.read("/a/b"))`. Scope
  subsumption is deferred; do not assume prefix semantics at the grant
  level.
- `PluginRuntime` is the per-host owner (executor-confined, like
  `FrameHost`). Install is all-or-nothing over `requires`; a required
  capability with no backing service fails closed
  (`serviceUnavailable`). Successful install and uninstall invalidate
  the owning host. Deinitializing the runtime deactivates every installed
  plugin. Two hosts, two runtimes: nothing is shared.
- `PluginRuntime` is explicitly non-`Sendable`; its unavailable conformance
  makes ordinary cross-executor use a compiler error. `install` takes a
  `sending` plugin because successful installation transfers that plugin's
  state and callbacks into the runtime. Commands, scenes, and observations
  remain on the owning host's executor.
- `PluginContext` carries the granted, unforgeable handles plus the
  plugin installation's observation context. That context forwards a
  plugin `Signal` change or `invalidate()` to exactly one owning host,
  but has its own cancellation lifetime: failed activation and uninstall
  detach only that plugin's observations.

## Contribution surface

- **Slots**: the app opts in with `PluginSlot("name", runtime:)` in
  ordinary view content. Plugins implement
  `render(slot:in:)` returning `RenderNode` (the framework's own value
  erasure boundary; plugins never hand the host a `some View`). Each
  plugin renders under a runtime-assigned child identity retained for
  that plugin ID. Removing an earlier peer therefore cannot renumber a
  surviving contribution or redirect focus/actions, while the existing
  `duplicateIDs` diagnostic keeps working.
- **Scenes**: plugins return `PluginSceneContribution`s from
  `scenes(in:)`. Contributed scene IDs are namespaced
  `plugin/<pluginID>/<name>`; the role may never be `.primary` (typed
  install error). The app opts in with `PluginScenes(runtime:)` in its
  `scenes` builder, after which shells treat contributed scenes exactly
  like `Window` declarations, including `openWindow` and
  `dismissWindow`. Contributions are read when the scene graph compiles:
  install plugins before creating the host or shell.
- **Commands**: plugins return `PluginCommand`s from `commands()`.
  `PluginRuntime.commands` exposes them in deterministic
  install-then-declaration order, each bound to its owning plugin's
  context; presentation (menu, palette, key binding) is the app's
  choice, and dispatch runs on the host's executor. A command value
  cached by an app becomes inert after its plugin is uninstalled.

## Service implementations

`GamaCore` and `GamaPlugin` are stdlib-only, so they define capability
interfaces (`HostServices`, `FilesystemProvider`). Implementations come
from the application, or from the platform-conditional
`GamaPlatformServices` target: `HostServices.standard` wires a stderr
log, a monotonic millisecond clock, and `FilesystemProvider.standard`.
No portable target may import `GamaPlatformServices`
(`check-boundaries.sh` enforces the inverse grep), so wasm32/Embedded
exclusion is structural. On platforms without an OS, `.filesystem` is
interface-only and required filesystem grants fail closed at install.

### Filesystem containment, V1 limits

Path checks are exact prefix containment on the absolute path as given:
no symlink resolution (a symlink inside a granted prefix can point
outside it: documented limitation), `.` and `..` components refused,
relative paths refused, internal empty components refused (one trailing
separator is accepted), empty prefixes deny everything, and containment
stops at path-component boundaries (a prefix `/a` never covers `/ab`).
`FilesystemAccess` checks before calling the provider, and
`FilesystemProvider.standard` re-checks before any I/O.

## Registration

There is no discovery in V1, deliberately. Static registration through
an explicit `install` list in application code is the only portable
mechanism (wasm32/Embedded cannot enumerate or load anything at
runtime):

```swift
var host = try FrameHost(app: app)
let plugins = PluginRuntime(
    grants: CapabilityGrants(table: ["dev.gama.demo.status": [.log, .clock]]),
    services: .standard,
    subscriptions: host.subscriptions
)
try plugins.install(StatusLinePlugin())
```

`Sources/GamaDemo/main.swift` is the working vertical slice: a status
line contributed through a slot using `.log` and `.clock`.

## Deferred (not in V1)

Tier 2 loading, Tier 3 process transport, `.network`, scope subsumption
and path normalization, manifest macros, discovery/scanning,
plugin-to-plugin dependencies, persistence, C-ABI changes, and shell
teardown of contributed windows on uninstall (a live contributed window
currently outlives `uninstall`; close it through window actions).
