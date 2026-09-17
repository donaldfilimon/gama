# 0009 — Signal and PluginRuntime are not Sendable

Status: Accepted. Supersedes [0004](0004-signal-confinement.md).

Implements `../superpowers/specs/2026-08-27-signal-redesign-design.md`
(approved 2026-08-27), with one measured correction recorded below.
Delivery evidence is maintained in `../Capabilities.md`.

## Context

ADR 0004 recorded `Signal` as `final class … : @unchecked Sendable` with
single-host confinement documented in a comment and enforced by nobody,
because GamaCore cannot import Synchronization. The honesty lived in prose.

That laundering propagated: every type that transitively held a signal had
to claim `Sendable` too — `View`, `App`, `Scene`, `BuildContext`,
`Binding`, `SubscriptionContext`, `GamaPluginProtocol`, plugin scene and
command contributions — and each of those claims was satisfiable *only*
because `Signal` lied at the bottom. Plugin V1 then introduced the same
executor-confined claim on `PluginRuntime` and its command lease.

## Decision

**`Signal` and `PluginRuntime` explicitly declare `~Sendable` and are also
unavailably `Sendable`.** The tilde declaration prevents implicit Sendable
inference and records the negative-conformance intent on the type itself. The
unavailable extension keeps the existing named diagnostic for a consumer who
attempts an unchecked retroactive conformance. Together they make the
confinement contract visible in source and produce a compiler error at ordinary
`Sendable` use:

```swift
public final class Signal<Value: Sendable>: ~Sendable { … }

public final class PluginRuntime: ~Sendable { … }

@available(*, unavailable)
extension Signal: @unchecked Sendable {}

@available(*, unavailable)
extension PluginRuntime: @unchecked Sendable {}
```

The laundering is removed everywhere it had spread. These types drop
`Sendable` because they are host-confined and always were:

| Type | Why it is confined |
| --- | --- |
| `View`, `Scene`, `App` | own `@State` signals and content closures |
| `BuildContext` | carries the host's action/key registration hooks |
| `Binding` | travels into child components within one build pass |
| `SubscriptionContext` | its invalidation hook captures the host's dirty signal |
| `GamaPluginProtocol`, `PluginRuntime`, `PluginContext`, plugin scene/command contributions | installed into, and run on, exactly one host |
| `HostActionStore`, `CompiledSceneGraph`, `SceneSurface` | hold host-local callbacks and mutable action/lifecycle state |

What stays `@Sendable`, deliberately, because it genuinely crosses
contexts: `HostServices` (log, clock, filesystem), the AppKit window
command channel (`enqueue`), and `ScenePayload`'s value operations.

`sending` appears only on public ownership-transfer operations:
`GamaHostView.init(app:)`, `GamaHostView.install(app:)`, `GamaWeb.install`,
`GamaEmbed.makeContext`, and `PluginRuntime.install`. Synchronous internal
plumbing (`AppRuntime`, `FrameHost`, scene compilation, and backend boxes)
does not pretend to cross an isolation domain.

## Correction to the spec (measured 2026-08-27)

The spec asserted the unavailable conformance "prevents the conformance
from ever being retroactively *fixed* by a consumer." **That is
overstated.** On the pinned 6.5-dev snapshot, a consumer writing

```swift
extension Signal: @retroactive @unchecked Sendable {}
```

compiles, with a warning: `'Signal<Value>' was declared with an
unavailable 'Sendable' conformance in 'GamaCore'; conforming here risks
data races [#UnavailableSendableConformance]`, plus a note pointing at the
declaration.

So the unavailable conformance buys a **named, attributable diagnostic a
consumer must silence deliberately**, not an impossibility. That is still
worth having, and it is strictly more than ADR 0004's comment — but the
stronger claim must not be repeated.

The spec's other verification item holds exactly as written: a signal
genuinely cannot cross a `@Sendable` closure boundary — that is a hard
error (`#SendableClosureCaptures`).

## Verification

- `Tests/CompileFail/SignalSendable.swift` and
  `Tests/CompileFail/PluginRuntimeSendable.swift` live outside every SwiftPM
  target. `scripts/check-concurrency-negative.sh` builds the modules and
  type-checks both with the exact pinned compiler; each must fail, name its
  type, diagnose the unavailable `Sendable` conformance, and point to the
  declaration. The gate runs from local `check.sh` and the existing macOS CI
  job, so no required status-check context changes.
- The measured retroactive-conformance warning remains pinned separately by
  `Tests/Fixtures/Confinement/warn.SendableConformanceIsFlagged.swift` in the
  boundary gate.
- The boundary gate also requires both `~Sendable` declarations and both
  adjacent unavailable `@unchecked Sendable` conformances, so removing either
  half of the combined contract fails before behavioral tests run.
- The concurrent-host isolation suites pass **unchanged** — they proved
  the property behaviorally; the type system now also states it.
- Zero runtime cost: region isolation and `sending` are language
  features. The Embedded size gate not regressing is the evidence.

## Consequences

- Source break for any external conformer that relied on `App: Sendable`
  or `View: Sendable`. In-repository conformers migrate atomically;
  `../SceneMigration.md` carries the note.
- `State` is no longer `Sendable`, matching the signal it wraps.
- `PluginRuntime.install` takes a `sending` plugin because successful install
  is an ownership transfer; cached commands remain host-local and revocable.
