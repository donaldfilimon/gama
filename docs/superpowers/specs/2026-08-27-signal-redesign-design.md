# Gama umbrella — Signal concurrency redesign (Slice C, wave 2)

Date: 2026-08-27. Status: **implemented** (Donald adopted the validated
candidate on 2026-08-27; the final declaration-layer contract includes plugin
V1). Delivery evidence is maintained in `docs/Capabilities.md`.

Supersedes `docs/adr/0004-signal-confinement.md`'s interim
`@unchecked Sendable` stance. ADR 0009 records the final shape.

## Problem

`Signal` (`Sources/GamaCore/State.swift:73`) is
`final class … : @unchecked Sendable` with documented-but-unenforced
host confinement, because GamaCore cannot import Synchronization
(Embedded-safe, stdlib-only). The compiler verifies nothing; the honesty
lives in comments. The 2026-08-27 fresh-agent baseline validated a design
that makes confinement compiler-checked at zero runtime cost.

## Decision

1. **`Signal` and `PluginRuntime` become non-Sendable, and unavailably so:**

   ```swift
   @available(*, unavailable)
   extension Signal: @unchecked Sendable {}

   @available(*, unavailable)
   extension PluginRuntime: @unchecked Sendable {}
   ```

   The unavailable declarations are load-bearing: ordinary `Sendable` use
   fails and points to them. On the pinned snapshot, a consumer can still add
   a retroactive `@unchecked` conformance, but the compiler emits the named
   `#UnavailableSendableConformance` data-race warning. This is a deliberate,
   attributable opt-out, not an impossible override.

2. **Region-based isolation moves state only at real ownership boundaries.**
   The public Apple install/initializer, WASM install, C-embed context factory,
   and plugin install operations use `sending`. `AppRuntime`, `FrameHost`,
   scene compilation, and private backend boxes are synchronous
   same-executor plumbing and do not use `sending`.

3. **`App` drops its `Sendable` requirement**
   (`Runtime.swift:101`). An app value owns non-Sendable signals, so the
   requirement is dishonest today (`@unchecked` launders it). Entry points
   that move an app across contexts take it `sending`. This is a source
   break for conformers that relied on `App: Sendable` — in-repository
   conformers are migrated atomically, and `docs/SceneMigration.md` gains
   the external migration note.

4. **The complete declaration layer is re-audited under the same lens.**
   `SubscriptionContext`, `Binding`, `State`, `HostActionStore`,
   `CompiledSceneGraph`, `SceneSurface`, `PluginRuntime`, plugin protocols,
   plugin contributions, and their callbacks are host-confined. Pure IDs,
   geometry, events, render/draw values, window payloads, capability values,
   encoded ABI data, `HostServices`, the window command channel, and
   `ScenePayload` value operations remain `Sendable` where they genuinely
   cross contexts.

## Verification

- The existing concurrent-host isolation suites must pass unchanged —
  they prove the property the type system now also states.
- `Tests/CompileFail/SignalSendable.swift` and
  `Tests/CompileFail/PluginRuntimeSendable.swift`, driven by the pinned
  `scripts/check-concurrency-negative.sh`, must fail type-checking with the
  unavailable-conformance diagnostic and declaration note. The separate
  retroactive-conformance fixture must continue to compile only with
  `#UnavailableSendableConformance`.
- Embedded, WASM, and Apple gates all green: region-based isolation and
  `sending` are language features, not runtime ones — the zero-cost claim
  is proven by the Embedded size gate not regressing.

Out of scope: any change to `Signal`'s observation API, storage, or the
FNV identity path; synchronization in `GamaCore`; or making pure transfer
values non-Sendable. Merge only on a green six-job matrix.
