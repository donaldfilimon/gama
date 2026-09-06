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

- [x] **`docs/Capabilities.md` overstated the per-surface `@Reactive` row —
      resolved 2026-09-06, in the opposite direction from this entry's own
      premise.** The four post-`77812d99` behavior changes it names
      (`ReactiveSlot._bind` clearing `bound` with no store, `FrameHost.pump`
      on a shared `buildFrame`, the narrowed `transientStateIDs` meaning,
      `GamaWebDemo` off `GamaMacros`) were still unpushed when this was
      written. They are not any more: `5dbdad8`, `8afa994`, `90f2f99`, and
      `befc7e3` are all ancestors of `7d6e2fb` (PR #81), whose six required
      jobs passed first-attempt as run `34048029135`. The row now attaches to
      `7d6e2fb` instead of `77812d99`, and the sentences calling the changed
      form locally proven at an unpushed `5dbdad8` are gone.
      Two further corrections came out of checking run state rather than
      trusting the file: the **Evidence snapshot named `bc2fe4d` as the
      current `origin/main` tip**, thirteen commits stale — it is `0d4cf12`,
      whose run `34049182287` finished six-for-six during this slice — and the
      suite is **299 tests in 54 suites**, not the 266 the row claimed nor the
      269 this entry claimed. Verified locally: `check-apple.sh`,
      `check-docs.sh`, and `check-doc-coverage.sh` all exit 0.

- [x] **Superseded by hosted proof 2026-09-06 — this line is no longer
      unpushed.** PR #83 merged as `98c150d`; its head `3f180f1` passed all six
      required acceptance jobs, and `98c150d^{tree}` is byte-identical to
      `3f180f1^{tree}`, so the hosted evidence covers this exact tree. The
      local record below stands as the pre-push evidence it was.
      **Local verification of the unpushed line.** At `5dbdad8`, eleven of the
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

- [x] **Superseded by hosted proof 2026-09-06.** Same merge, same tree
      identity: the adaptive terminal surface is hosted proven at `98c150d`.
      **Local verification of the adaptive terminal surface.** At `1e2b688`,
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

- [x] **Should any refactor start while the adaptive-terminal work sits
      unpushed and unreviewed in the shared checkout?** Answered by events
      2026-09-06 rather than by argument: a peer session pushed that line to
      `origin/feat/adaptive-terminal-surface` and opened **PR #83**, which
      carries the refactor slice `dc7e847` and both ledger commits along with
      it. The refactor did not need to wait, and it did not end up as the
      standalone PR against `0d4cf12` that the handoff report proposed — it is
      bundled into #83. Recorded because the report said otherwise.
- [x] **Is the correct outcome for the remaining `scripts/` duplication "no
      slice"?** Yes. `SCRATCH_ROOT` fallback and Swift-version repetition
      stayed untouched: with #82 and the home-path sweep in place neither can
      go stale silently, and no defect was demonstrated for either. No
      candidate replaces it; candidates 3-5 remain not recommended for the
      same reason.

- [ ] **PR #85 carries the uncorrected `CellSerializer` spec, and the fix is
      unpushed.** Its head `cf0c369` has the code but not `eeb2426` /
      `0f498d5`, so merging it as-is lands a spec asserting that a one-byte
      HTML change breaks the WASM browser marker and that an encoding change
      breaks `check-c-abi.sh`. Both were verified false: the marker reads
      `root.textContent` through a regex (`WebHost/gama.js:174-196`), and
      `Examples/CEmbed/main.c:8` checks length plus the `GAMA` magic but no
      draw command. It also lacks the `GamaAppleUI` third conformance and the
      exact-string HTML test. Peers `gama-13` and `abbey-bot-94` were notified
      2026-09-06 15:5x; no reply yet. **Publishing needs the user's
      authorization, which has not been given, so this is recorded rather than
      resolved.**

- [ ] **PR #84 is safe on the code but falsifies two lines of
      `docs/Testing.md`, and no gate can catch it.** The split is genuinely
      move-only: 55 `@Test` names, 12 `@Suite` names, and the suite-to-test
      binding are byte-identical across the diff, the only semantic change
      being `TestBox` losing `private` because two split files now need it.
      All six required jobs pass on the exact head `e014217`. After merge,
      `docs/Testing.md:38` still lists the deleted `gamaTests.swift` and none
      of the ten new files, and `:57` still calls `TestBox` "file-local" when
      it is now target-internal. `check-doc-links.py` validates relative links,
      not backticked file references, which is exactly why CI stays green while
      the table is wrong. Also worth deciding: `ViewBuilderTests.swift`
      declares `struct BuilderTests`, so `--filter ViewBuilderTests` matches
      nothing and **exits zero** — the documented silent-filter hazard, in a
      file this PR creates.
- [ ] **Baseline correction to my own reporting.** I cited "304 tests in 55
      suites" as the suite size. That is the **local** figure at `148b6da`,
      which includes the unpushed `CellSerializerTests` (5 tests, 1 suite).
      `origin/main` at `98c150d` measures **299 in 54**, and 299 + 5 = 304,
      54 + 1 = 55, so the two reconcile exactly. Anywhere the hosted baseline
      is meant, 299/54 is the number.

- [x] **PR 1 delivered 2026-09-06: `scripts/evidence-freshness.py` +
      `scripts/check-evidence-freshness.sh`, self-test green, deliberately NOT
      in the `gates=(...)` array.** Run against the real ledger it exits 1 and
      names all 20 unannotated rows, which is the correct red state before
      PR 2. Its self-test proves ten cases on a scratch repo under `$TMPDIR`
      (never inside this iCloud tree): fresh passes; committed drift fails;
      uncommitted drift fails; `unverified` with drift passes; `unverified`
      *without* drift fails; a missing anchor fails; a non-ancestor anchor
      fails; an unannotated row fails; a renamed table header fails with "zero
      rows parsed"; a shallow clone fails. The self-test caught a real fixture
      bug on first run — it wrote "Hosted proven" prose while setting
      `layer=unverified`, and the lead-word binding rejected it, which is the
      binding working.
- [ ] **PR 2: annotate all 20 rows and enable the gate in one commit.**
      A fail-closed fourteenth gate that fails when a capability row's anchor
      commit predates changes to the files that row depends on. Design decided:
      a strict inline HTML-comment annotation per row
      (`layer=`/`anchor=`/`paths=`), parsed by `scripts/evidence-freshness.py`
      behind a thin bash wrapper, in the `check-docs.sh`/`check-doc-links.py`
      shape. Locality is the anti-drift property — a separate manifest
      reintroduces the very split-file drift being fixed. Totality is the
      fail-closed hinge: zero rows parsed, or any row without an annotation, is
      a hard failure, mirroring `check-toolchain-pins.sh`'s count guard.
      Introduces an **Unverified** vocabulary term whose rule is inverted —
      absence of drift fails — so a row cannot be parked there after the drift
      is repaired. Needs `fetch-depth: 0` on the macOS CI job, since anchors are
      unreachable in a depth-1 clone. Land as two PRs: script plus self-test
      first, then annotate all twenty rows and enable in one commit, never in
      batches.
      Known limits worth keeping: it proves freshness, not that the anchor's run
      passed (no network); `paths` remains human judgment; it is content-blind,
      so a comment fix counts as drift; and it couples to true merges — a switch
      to squash-merge would break the ancestry check loudly.

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
