# 0009 — Signal is not Sendable; confinement is compiler-checked

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
because `Signal` lied at the bottom.

## Decision

**`Signal` is not `Sendable`, and unavailably so.** The confinement the
comment described is now a fact the compiler checks:

```swift
public final class Signal<Value: Sendable> { … }

@available(*, unavailable)
extension Signal: @unchecked Sendable {}
```

The laundering is removed everywhere it had spread. These types drop
`Sendable` because they are host-confined and always were:

| Type | Why it is confined |
| --- | --- |
| `View`, `Scene`, `App` | own `@State` signals and content closures |
| `BuildContext` | carries the host's action/key registration hooks |
| `Binding` | travels into child components within one build pass |
| `SubscriptionContext` | its invalidation hook captures the host's dirty signal |
| `GamaPluginProtocol`, `PluginContext`, plugin scene/command contributions | installed into, and run on, exactly one host |

What stays `@Sendable`, deliberately, because it genuinely crosses
contexts: `HostServices` (log, clock, filesystem), the AppKit window
command channel (`enqueue`), and `ScenePayload`'s value operations.

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

- `Tests/Fixtures/Confinement/` holds negative fixtures outside every
  SwiftPM target, driven by `scripts/check-boundaries.sh`: `error.*` must
  fail to compile, `warn.*` must compile *and* emit the named diagnostic.
  Folded into the existing boundaries gate rather than a new CI job,
  because the six required status-check contexts are name-pinned in the
  repository ruleset and adding a job would orphan them.
- The concurrent-host isolation suites pass **unchanged** — they proved
  the property behaviorally; the type system now also states it.
- Zero runtime cost: region isolation and `sending` are language
  features. The Embedded size gate not regressing is the evidence.

## Consequences

- Source break for any external conformer that relied on `App: Sendable`
  or `View: Sendable`. In-repository conformers migrate atomically;
  `../SceneMigration.md` carries the note.
- `State` is no longer `Sendable`, matching the signal it wraps.
