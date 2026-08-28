# 0004 — Signal confinement and the Synchronization ban

Status: **Superseded** by [0009](0009-signal-is-not-sendable.md)
(2026-08-27). Kept for the history of why the interim stance existed and
amended with the final declaration-layer contract below.

## Context

`GamaCore` must stay Embedded-Swift-safe: stdlib only, so importing
`Synchronization` (Mutex) is banned by the boundary gate. Yet
`App: Sendable` requires the state types it reaches (`Signal`,
`HostActionStore`) to be Sendable, and there is no checkable lock to back
that up.

## Decision

`Signal` and `HostActionStore` are `@unchecked Sendable` under a documented
executor-confinement contract: each is confined to its owning host's
executor and never shared across concurrent hosts. The contract is stated
at each conformance site, and the compile-time enforcement that copies of a
host cannot smuggle state across owners comes from ADR 0006's noncopyable
hosts. GamaAppleUI adds `@MainActor` as real enforcement on its path.

## Consequences

Cross-thread misuse is preventable by convention plus noncopyability, not
by the type system alone; the honest fix candidates (per-field
`nonisolated(unsafe)`, dropping `App: Sendable`, or a custom lock-free
design) stay Proposed in `tasks/todo.md` Slice C until Donald picks one.

## Superseding contract

The approved Slice-C implementation chose the non-Sendable design. `Signal`
and the later `PluginRuntime` declaration are ordinary final classes with
`@available(*, unavailable)` `@unchecked Sendable` conformances. Normal
attempts to use either as `Sendable` fail and point at that declaration. The
pinned compiler still permits a consumer to add a retroactive `@unchecked`
conformance with `#UnavailableSendableConformance`; this is a named warning,
not an impossible override.

The executor-confined declaration layer no longer launders that state:
`App`, `Scene`, `View`, `State`, `Binding`, `SubscriptionContext`,
`HostActionStore`, `CompiledSceneGraph`, `SceneSurface`, plugin protocols,
plugin contributions, and their host-local callbacks are not `Sendable`.
Pure transfer values remain `Sendable`, as do the host-service and window
command closures that genuinely cross an executor boundary. Public install
operations use `sending` only when they transfer an app or plugin region into
a long-lived Apple, WASM, C-embed, or plugin-runtime owner.

No lock, synchronization framework, global actor, or runtime cost was added to
`GamaCore`.
