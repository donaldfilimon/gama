# 0004 — Signal confinement and the Synchronization ban

Status: Accepted (interim) — a redesign is a ledgered Slice C proposal.

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
