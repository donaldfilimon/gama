# SwiftData-backed persistence of selected `@Reactive` state — draft

Status: Draft. Open questions, not a commitment. Nothing here is built.
Roadmap track 4, second half
([native UI roadmap](../2026-09-29-native-ui-roadmap-design.md)). The first
half, SwiftUI embedding, is
[its own design](../2026-09-29-swiftui-embedding-design.md).

## The ask

Some per-surface state should survive relaunch: a selected tab, a split
position, a text field draft, the expanded rows of an outline. Today every
`@Reactive` value lives in the owning `FrameHost`'s state store, keyed by
`(NodeID, slot index)`, and dies with the host. The roadmap asks for a store
in the platform-services layer that saves and restores **selected** reactive
values through SwiftData, with no new import in the portable core.

## Constraints already settled elsewhere

- `GamaCore` stays stdlib-only. It may gain a portable seam (a protocol or a
  closure table), never a SwiftData or Foundation import.
  `scripts/portable-global-state.py` enforces this.
- `GamaPlatformServices` is the Foundation-backed service layer, importable
  only by applications, demos, examples, and tests. Whether SwiftData goes
  there or into a new Apple-only services target is open question 1.
- `docs/AppleIntegration.md` currently says SwiftData belongs to the
  application persistence layer and that loading or saving never happens
  inside a per-frame content closure. This draft must not break the second
  rule, and changes the first only if the owner accepts it.
- `@Reactive` is per-surface (ADR 0011). Persisted state is therefore keyed
  per surface, not per app, unless the owner decides otherwise.
- `FrameHost.transientStateIDs` reports storage replaced at an existing key.
  Restoration must not register as a transient replacement.

## A candidate shape (for discussion only)

```text
@Reactive(persisted: "sidebar.width") var width = 240     // opt-in, per slot
  -> ReactiveSlot carries a persistence key (portable String)
  -> FrameHost exposes a portable ReactivePersistence seam:
       restore(key, surface) -> encoded value?
       record(key, surface, encoded value)
  -> an Apple-only SwiftData adapter implements the seam:
       @Model PersistedReactiveValue { surfaceKey, slotKey, payload, updatedAt }
  -> the host batches writes and saves off the frame path
```

Encoding needs a portable, stdlib-only representation. `Codable` is
stdlib, but its encoders (JSON, property list) are Foundation; the portable
seam would hand the adapter `Codable` values and let the Apple side encode.

## Open questions for the owner

1. **Which target owns SwiftData?** `GamaPlatformServices` (already
   Foundation-backed, but today platform-neutral in intent) or a new
   Apple-only `GamaAppleServices` target that can import SwiftData without
   making `GamaPlatformServices` Apple-only?
2. **Opt-in syntax.** A macro argument (`@Reactive(persisted:)`), a
   view modifier (`.persisted("key")` on a subtree), or an explicit
   registration call on the surface? The macro route touches
   `GamaMacrosImpl` and its expansion tests.
3. **Key stability.** `(NodeID, slot)` changes whenever the view structure
   changes, so it cannot be a storage key across app versions. Is an explicit
   string key mandatory, and what happens when two slots claim one key in one
   frame (the native-region and control tables keep the last registration)?
4. **Surface identity across launches.** A `WindowGroup` payload identifies a
   surface within one run. What identifies "the same window" after relaunch,
   and does the macOS shell's missing placement restoration (not shipped) need
   to land first?
5. **Value types.** Only `Codable & Sendable` values, or an explicit
   allowlist of scalar types to keep migration simple?
6. **Schema migration.** Who owns `VersionedSchema` and migration plans: the
   framework target, or the application, which already owns its own
   `ModelContainer`? Sharing one container with the app's schema is simpler
   for the app and riskier for Gama.
7. **Write timing.** Save on every change, debounce, or on
   `didEnterBackground`/`willTerminate` only? `GamaView` in SwiftUI does not
   deliver those lifecycle events today (open question 1 of the embedding
   design), so the answer interacts with that one.
8. **Other backends.** Does the portable seam get a TUI (file-backed) or web
   (`localStorage`) adapter, or is persistence Apple-only by decision?
9. **Privacy.** A persisted text field draft may hold sensitive text. Is
   there an opt-out per field, and should secure fields be refused outright?

## What would count as done, if accepted

A portable seam tested without Apple frameworks, an adapter tested against an
in-memory `ModelContainer`, a relaunch round-trip test, a migration test, and
a `docs/Capabilities.md` row at whatever layer those gates support.
