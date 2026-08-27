# Gama umbrella — Signal concurrency redesign (Slice C, wave 2)

Date: 2026-08-27. Status: **approved** (Donald adopted the validated
candidate on 2026-08-27; this document records the design). Delivery
evidence is maintained in `docs/Capabilities.md`.

Supersedes `docs/adr/0004-signal-confinement.md`'s interim
`@unchecked Sendable` stance once implemented; ADR 0004 is then marked
Superseded with a pointer here and a new ADR records the final shape.

## Problem

`Signal` (`Sources/GamaCore/State.swift:73`) is
`final class … : @unchecked Sendable` with documented-but-unenforced
host confinement, because GamaCore cannot import Synchronization
(Embedded-safe, stdlib-only). The compiler verifies nothing; the honesty
lives in comments. The 2026-08-27 fresh-agent baseline validated a design
that makes confinement compiler-checked at zero runtime cost.

## Decision

1. **`Signal` becomes non-Sendable, and unavailably so:**

   ```swift
   @available(*, unavailable)
   extension Signal: Sendable {}
   ```

   The unavailable conformance is load-bearing: it prevents the conformance
   from ever being retroactively "fixed" by a consumer, so single-host
   confinement is a compiler-enforced fact rather than a comment.

2. **Region-based isolation moves signals between contexts.** Construction
   sites that hand state into a host use `sending` transfer
   (`func install(app: sending A)`-style signatures on the few entry
   points that cross an isolation boundary), so a signal region transfers
   into the host instead of being shared with it.

3. **`App` drops its `Sendable` requirement**
   (`Runtime.swift:101`). An app value owns non-Sendable signals, so the
   requirement is dishonest today (`@unchecked` launders it). Entry points
   that move an app across contexts take it `sending`. This is a source
   break for conformers that relied on `App: Sendable` — in-repository
   conformers are migrated atomically, and `docs/SceneMigration.md` gains
   the external migration note.

4. **`SubscriptionContext`/`Binding` are re-audited under the same lens**:
   whatever remains genuinely cross-context (the host-invalidation hook)
   keeps an explicit, narrow `@Sendable` closure; nothing else stays
   `@unchecked`.

## Verification

- The existing concurrent-host isolation suites must pass unchanged —
  they prove the property the type system now also states.
- New compile-time tests (a `#if compiler` guarded no-compile harness or
  macro-expansion-style negative fixtures, matching how the repo tests
  diagnostics) pin: `Signal` cannot cross a `@Sendable` closure boundary;
  the unavailable conformance cannot be shadowed.
- Embedded, WASM, and Apple gates all green: region-based isolation and
  `sending` are language features, not runtime ones — the zero-cost claim
  is proven by the Embedded size gate not regressing.

Out of scope: any change to `Signal`'s observation API, storage, or the
FNV identity path. Merge only on a green six-job matrix.
