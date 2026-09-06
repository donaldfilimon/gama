# Todo

This ledger contains current work only. Completed delivery history remains in
Git, merged pull requests, dated ADRs, and `docs/superpowers/`. Capability
status is authoritative in `docs/Capabilities.md`.

## Maintenance delivery

Documentation, state-ownership, and browser-diagnostic maintenance uses the
same acceptance requirements as other code changes: review the final commit,
require all six hosted acceptance jobs before integration, and verify the
integrated `main` commit. A successful baseline run does not prove later
changes, and local verification does not replace hosted proof.

- [ ] **`docs/Capabilities.md` overstates the per-surface `@Reactive` row.** It
      reads "Hosted proven 2026-09-04 at merge commit `77812d99` ... 266 tests
      in 49 suites are green". Commits after that merge changed the behavior
      the row describes: `ReactiveSlot._bind` now clears `bound` when there is
      no store, `FrameHost.pump` was refactored onto a shared `buildFrame`,
      the documented meaning of `transientStateIDs` was narrowed, and
      `GamaWebDemo` dropped `GamaMacros` for direct `ReactiveSlot` binding.
      The suite is 269, not 266. By this ledger's own rule the hosted-proven
      claim attaches to `77812d99` only; it does not carry to the unpushed
      commits, and the row should say so until a hosted run covers them.

- [ ] **Local verification of the unpushed line.** At `5dbdad8`, eleven of the
      thirteen `scripts/check.sh` gates ran in an isolated `/private/tmp`
      worktree and all passed: `check-apple.sh` (271 tests in 50 suites),
      `check-apple-platforms.sh`, `check-boundaries.sh`,
      `check-concurrency-negative.sh`, `check-c-abi.sh`, `check-embedded.sh`
      (636,792-byte linked artifact), `check-linux.sh`, `check-wasm.sh`,
      `check-android.sh`, `check-docs.sh`, and `check-doc-coverage.sh`.
      Not run: `check-android-emulator.sh` (no booted emulator) and
      `check-mlir.sh` (no local `mlir-opt`, and it hardcodes
      `/private/tmp/gama-framework-swiftpm` with no override, so it would
      collide with a concurrent session). This is local evidence for one
      commit on an advancing branch. It is not hosted proof and does not
      substitute for the six-job matrix on a pushed commit.

- [x] **`docs/Capabilities.md` evidence fidelity.** Three claims were stale
      against measurement and have been corrected: the evidence snapshot cited
      run `33919361432` at `77812d99` when the current `origin/main` tip
      `bc2fe4d` has its own six-job green run `33931402885` (verified by
      `headSha`, and honest that its WebAssembly job passed only on a re-run
      after a Chrome-launch flake); the per-surface `@Reactive` row asserted a
      volatile "266 tests in 49 suites" that was already wrong at three later
      commits, now dropped in favour of the named suites the row already
      lists; and the Embedded row's 631,960-byte artifact is now tagged to its
      2026-09-04 measurement beside the 636,792 bytes measured at `5dbdad8`.
      The row's changed-WASM-form caveat is now discharged locally and still
      open hosted.

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
- Migrating the 17 `@_cdecl` entry points in `GamaEmbed` (8) and `GamaWASM`
  (9) to `@c`. Measured against the pinned snapshot on 2026-09-06: `@c` is
  implemented and takes a bare identifier (`@c(name)`, not `@c("name")`), but
  it emits only the C symbol where `@_cdecl` emits the C symbol plus the
  Swift-mangled one, on public and non-public declarations alike. That is an
  emitted-symbol change to the versioned `gama_embed_v1_*` and
  `gama_web_v1_*`/`gama_web_v2_*` surfaces, so it needs an accepted design and
  a version decision, not a refactor pass. `check-portable-symbols.sh` would
  not catch it: that gate scans undefined symbols only. `@_extern` has no
  unprefixed `@extern` form in this snapshot (`unknown attribute 'extern'`),
  so the seven `GamaWASM` sites stay as they are.
