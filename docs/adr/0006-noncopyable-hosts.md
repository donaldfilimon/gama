# 0006 — Noncopyable hosts

Status: Accepted.

## Context

`FrameHost` is a struct owning live reference state (action tables, the
dirty signal, subscriptions). A copied host silently shared all of it —
two "independent" values invalidating and consuming each other's actions.
The 2026-08-27 integration incident proved the hazard from another angle:
a merge that dropped the annotations left main claiming value semantics
the implementation does not have.

## Decision

`FrameHost` and `AppRuntime` are `~Copyable`. `invalidate()` is
non-mutating (the dirty signal is a `let` reference), so a borrowed host
can request frames. Backends own exactly one host per application
instance, boxed in a reference owner when closures need it.

## Consequences

Accidental sharing is a compile error; backend authors must pass hosts
`inout`/`borrowing`/`consuming` (documented in
`GamaCore.docc/BackendAuthoring.md`); Swift Testing property-access
`#expect` needs value binding first; conformances that require `Copyable`
cannot be added to hosts without revisiting this record.
