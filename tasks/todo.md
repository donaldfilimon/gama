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

- [ ] **Local verification of the adaptive terminal surface.** At `1e2b688`,
      eleven of the thirteen `scripts/check.sh` gates ran in the main checkout
      and all passed: `check-apple.sh` (299 tests in 54 suites),
      `check-apple-platforms.sh`, `check-boundaries.sh`,
      `check-concurrency-negative.sh`, `check-c-abi.sh`, `check-embedded.sh`,
      `check-linux.sh`, `check-wasm.sh`, `check-android.sh`, `check-docs.sh`,
      and `check-doc-coverage.sh`. Not run: `check-android-emulator.sh` (no
      booted emulator) and `check-mlir.sh` (no local `mlir-opt`). Separately,
      an out-of-repository probe exercised the process boundary that unit
      tests cannot reach: piped, it emits declared lines and exits with the
      declared code, message on stderr; under a pty the same binary renders
      the grid with cursor-positioning ANSI. That probe is what caught a hang
      in an input-less run that every unit test had passed over. This is local
      evidence for one commit on an advancing, unpushed branch. It is not
      hosted proof, and no row in `docs/Capabilities.md` may be promoted on
      it.

## Refactor audit (2026-09-06, base `origin/main` `0d4cf12`)

Baseline: 21 targets, ~11k lines of Swift/C. `GamaCore` 3,946 lines in 13
files; next largest are `GamaPlugin` 972, `GamaDraw` 871, `GamaTUI` 854.
Toolchain split intact (`.swift-version` `main-snapshot-2026-08-21`,
`Package.swift` `swift-tools-version: 6.4`). PRs #80, #81, #82 are all merged;
#80 auto-resolved once its five commits landed via #81.

**Overlap risk is local, not in the PRs.** The shared checkout's `main`
(`2580636`) carries ten commits and roughly 1,565 lines that are on no remote:
`AdaptiveSurface.swift`, `StreamPresenter.swift`, `Completion.swift`, three
test files, and `refactor(tui): present through AnsiPresenter rather than
around it`. Anything touching `GamaTUI`, `GamaCore`, or `GamaDraw` collides
with it.

Candidates, in order:

- [ ] **Duplicated gate preamble in `scripts/`.** The `SCRATCH_ROOT` fallback
      chain is repeated in 8 scripts, a Swift-version assertion in 12, and a
      `GAMA_TOOLCHAIN_ID` default in 11; `scripts/lib/manifest.sh` is existing
      precedent for a shared helper. **Corrected: this is not cosmetic.**
      `bundle-web.sh`, `check-wasm.sh`, `check-android.sh`,
      `check-embedded.sh`, and `check-linux.sh` each hardcode an absolute
      `/Users/donaldfilimon/...xctoolchain` path as the `GAMA_SWIFT_64`
      fallback — correct on exactly one machine and silently wrong on every
      other, inside gates meant to fail closed. CI never reaches those
      defaults because `ci-install-swift-snapshot.sh` exports the variables,
      so it is a portability defect rather than a CI defect.
      **Delivered `dc7e847`.** `scripts/lib/toolchain.sh` is tracked and all
      five scripts source it; no `/Users/<name>` path remains under `scripts/`.
      `check-toolchain-pins.sh` now asserts those scripts route through the lib
      instead of repeating the literal, and fails on any checked-in home path,
      so the class cannot return. Mutation-verified both directions; eleven of
      the thirteen `check.sh` gates green and two NOT RUN for missing local
      prerequisites. The fifth rewired script, `bundle-web.sh`, is **not** in
      the gate array at all — it is the Pages deploy path, so it got a
      `bash -n` plus the byte-identical path proof here, and hosted Pages CI is
      its only real exercise. The `SCRATCH_ROOT` and Swift-version repetitions above are
      untouched and remain cosmetic: no defect was demonstrated for either.
- [ ] `Sources/GamaTUI/Terminal.swift` holds POSIX and Windows Console in one
      678-line file (`// MARK` at :77 and :442). Pure file split, no
      demonstrated defect, and it sits under the unpushed `AnsiPresenter`
      work. Not recommended.
- [x] **Codec/ABI validation — rejected, keep as is.** `DrawList.encode/decode`
      centralizes the wire format with `throws(DecodeError)`; magic and version
      are validated once at `DrawList.swift:179-182`. No backend re-decodes.
- [x] **Apple host/session ownership — rejected, keep as is.** The risks the
      brief names are already handled and commented: subscription cancellation
      on reinstall (`GamaHostView.swift:218-224`), bounded font cache with
      written rationale (`:136`, `:408`), 14 explicit `@MainActor` annotations.
- [x] **Plugin lifecycle — rejected on this evidence.** Ten files, largest
      `PluginRuntime.swift` at 247 lines. No duplication found at this depth.

Open questions blocking implementation:

- [ ] Should any refactor start while ten commits of adaptive-terminal work sit
      unpushed and unreviewed in the shared checkout?
- [ ] If the remaining `scripts/` duplication is cosmetic now that #82 guards
      it, is the correct outcome "no slice", and if so which candidate replaces
      it?

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
- A wholesale-serialization abstraction over a painted grid, if the family is
  worth naming at all. Adaptive-surface phase 5 proposed conforming `GamaWASM`
  and `GamaEmbed` to `CellPresenter` and was **closed without implementation**
  on 2026-09-06: neither calls `presentDiff()`, so the protocol's swap contract
  is false for them, and both reach the grid through
  `HostPump.advance(into:emit:)` whose `emit` borrows the buffer, so a
  conformance could have no call site. The honest shape would be non-mutating,
  `borrowing CellBuffer -> Output`, which `HTMLSerializer.grid(from:)` and
  `DrawList.from(_:).encode()` already satisfy verbatim. That is new design and
  needs its own accepted record. Phases 1-4 shipped; see `tasks/goals.md`. The
  surface is distinct from the `CLI veneer` above, which is a packaging tool.
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
