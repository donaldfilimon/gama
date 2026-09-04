# Todo

This ledger contains current work only. Completed delivery history remains in
Git, merged pull requests, dated ADRs, and `docs/superpowers/`. Capability
status is authoritative in `docs/Capabilities.md`.

## Open implementation work

- [ ] Prove per-surface `@Reactive` state on a second and third backend: the
      [view-state design](../docs/superpowers/specs/2026-08-29-view-state-identity-design.md)
      asks `check-wasm.sh` and `check-android-emulator.sh` for behavioral proof
      beyond the Apple suite. The core, macros, diagnostics, Embedded
      compatibility, and host-less rendering landed under
      [ADR 0011](../docs/adr/0011-reactive-state-is-per-surface.md).
- [ ] Decide and implement `StrictMemorySafety` and
      `InternalImportsByDefault` together with warning promotion. Merely
      enabling strict-memory-safety warnings is insufficient because the
      ordinary build does not promote them to errors.

## Manual and credential-gated acceptance

- [ ] Exercise the AppKit accessibility adapter with VoiceOver and the UIKit
      path with a screen reader. Automated tests prove the derived text and
      bridge, not real assistive-technology interaction.
- [ ] Run the Developer ID signing and notarization path with valid credentials
      before describing the notarized macOS artifact as proven.
- [ ] Run the supplemental macOS shell smoke for Dock reopen, multi-window
      focus, close behavior, and Command-Q. Automated offscreen tests remain
      the gate; this item records the separate human-facing layer.

## Deferred product scope

These are not committed implementation work. Each needs a new accepted design
before execution:

- Tier 2 dynamically loaded plugins and Tier 3 out-of-process plugins.
- A versioned network capability and stronger filesystem/symlink confinement.
- UIKit-native scene ownership, Windows GUI hosting, and physical Embedded
  hardware acceptance.
- Additional distribution formats: Embed SDK, Linux/Windows staged products,
  Android release/keystore packaging, CLI veneer, and iOS-family archives.
