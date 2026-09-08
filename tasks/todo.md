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

- [x] **Duplicated gate preamble in `scripts/`.** The `SCRATCH_ROOT` fallback
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
- [x] `Sources/GamaTUI/Terminal.swift` holds POSIX and Windows Console in one
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

- [x] **PR #85 carries the uncorrected `CellSerializer` spec, and the fix is
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

- [x] **PR #84 merged as `dfc0f95`; the two `docs/Testing.md` lines it
      falsified are now fixed (2026-09-06).** Both were verified false on the
      merged tree before editing: `gamaTests.swift` is deleted yet line 38 still
      listed it, and `TestBox` moved to `TestSupport.swift` as target-internal
      while line 57 still called it "file-local". The table now carries all ten
      topic files plus `TestSupport.swift`, mapped from the actual `@Suite`
      names in each file rather than from the PR description, and it records
      that `ViewBuilderTests.swift` declares `struct BuilderTests`, so
      `--filter ViewBuilderTests` matches nothing and exits zero.
      Original review finding, kept for the record: The split is genuinely
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
- [x] **`ViewBuilderTests` filter hazard closed 2026-09-06.** The suite
      struct is now `ViewBuilderTests`; `--filter ViewBuilderTests` ran 5
      tests in 1 suite (exit 0 with a non-zero count). `AppleHostTests`
      likewise matches `--filter AppleHostTests` (2 tests). `docs/Testing.md`
      no longer tells the reader to filter on `BuilderTests`.
- [x] **Baseline correction to my own reporting.** I cited "304 tests in 55
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
- [x] **PR 2 delivered 2026-09-06: all 20 rows annotated, gate enabled as the
      fourteenth entry in `scripts/check.sh`, `fetch-depth: 0` added to the
      macOS CI job.** Mutation-proven red and green in both shapes that matter:
      a modified file inside an annotated path, and an **untracked new file**
      inside an annotated directory — the second is the shape the original
      drift actually took, since `Sources/GamaCore/Completion.swift` was new
      rather than modified.
      The gate immediately caught two things during its own enablement.
      `Android/JNI` claimed hosted proof while linking a `GamaEmbed` that had
      changed. And adding the gate to `.github/workflows/ci.yml` demoted four
      rows that list the workflow as a dependency. I considered narrowing those
      paths to `Toolchains.toml` to keep them green and **rejected it**:
      narrowing a gate's scope to suit the person who just tripped it is the
      failure mode this repository exists to prevent. The run at `3f180f1` did
      execute a different workflow than the tree now holds, so the demotion is
      true, and the next hosted run re-anchors them.
      Resulting picture, which is an accurate description of a tree with 18
      unpushed commits and no hosted run over them: 1 hosted, 10 locally,
      1 implemented, 8 unverified.
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

- [x] **ADR 0003 was Accepted and unenforced; now gated (2026-09-06).**
      "Swift Testing only; XCTest is banned" was a live decision that nothing
      checked — every mention of XCTest under `scripts/` and
      `.github/workflows/` was a *comment*. An `import XCTest` would have
      compiled and merged green. `check-boundaries.sh` now scans every Swift
      source under `Sources/` and `Tests/` by discovery rather than by a file
      list, so a new directory cannot escape it. Mutation-proven three ways:
      green on a clean tree, exit 1 on a planted import naming the file, and
      **green on a commented-out import**, which is the false-positive a naive
      `grep XCTest` would have produced.

- [x] **Spike 2026-09-06: can the Windows console path be gated locally?
      No — and the attempt would be worse than the gap.** Measured on this Mac
      with the pinned compiler:
      - The triple is recognized (`-print-target-info -target
        x86_64-unknown-windows-msvc` returns a valid target block), so it
        *looks* checkable.
      - It is not. `swiftc -typecheck -target x86_64-unknown-windows-msvc`
        fails with `unable to load standard library for target
        'x86_64-unknown-windows-msvc'`. The installed SDKs are static-linux,
        android, and wasm only, and `Toolchains.toml [windows_exception]` pins
        a Windows `.exe` installer, not a cross-compilation SDK. Unlike Linux,
        Android, and WASM, Windows has no local cross route by design.
      - **The trap:** a plain `swiftc -typecheck` of
        `Sources/GamaWindowsConsoleSmoke/main.swift` on macOS **exits 0**. It
        proves nothing, because `#if os(Windows)` elides the real code and only
        the three-line `#else` fallback (lines 35-37) is compiled. A gate built
        that way would pass forever while the Windows implementation rotted —
        the same vacuous-pass family this repo already documents for
        `-typecheck` on `~Copyable` code, and the same shape as the
        `HTMLSerializer` call site that only `check-wasm.sh` type-checks.
      **Recommendation: leave Windows ungated locally and keep this record**, so
      the gap is not later "fixed" by a gate that is green by construction.
      Windows proof stays the CI job, and the capability row must keep saying so.

- [x] **Two live policy violations fixed 2026-09-06, both mine.**
      (1) `docs/Capabilities.md` asserted "no randomized or fuzz codec test
      exists anywhere under `Tests/`" and deleted the word "randomized" from
      the DrawList/C ABI row on that basis. The claim was **false**:
      `Tests/gamaTests/ModernTests.swift:101` is
      `@Test("deterministic randomized frames round-trip")`, 256 LCG-driven
      frames through encode/decode. I had grepped three files and none of them
      was `ModernTests.swift`, then stated a universal. The word is restored
      and the correction recorded in the row. No hostile-input *fuzzer* exists,
      which is a different and unclaimed thing.
      (2) `AGENTS.md`, `CONTRIBUTING.md`, and `docs/Verification.md` all said
      thirteen gates while `scripts/check.sh` ran fourteen — I added the
      fourteenth and updated none of them. All three now say fourteen and both
      tables carry the new row.
- [x] **H3 + H6(b) + L1 closed 2026-09-06 by `scripts/check-package-graph.sh`,
      the fifteenth gate.** It reads `swift package dump-package` and asserts
      ADR 0012's strict-memory-safety scope on every shipped Swift target, the
      zero-runtime-package-dependency guarantee, `Extern` scoped to `GamaWASM`,
      and the `NonisolatedNonsendingByDefault` ban. Mutation-proven on all
      three: dropping `strictMemorySafety` from `GamaDraw`, giving `GamaTUI` a
      `SwiftSyntax` product dependency, and leaking `Extern` to a second target
      each fail with the offending target named.
      The exemption is **derived, not listed**: a target escapes the strict
      requirement only if it has no `.swift` file on disk. `GamaEmbedABI` and
      `GamaTUISignal` qualify today (0 Swift, 2 C files each), and either would
      stop qualifying the moment it gained Swift — a name-based allowlist would
      not have noticed. It also fails when zero shipped targets are inspected,
      so a manifest reshape cannot silently reduce it to checking nothing.
      All three gate-counting documents were updated in the same commit, which
      is the omission that made M2 a live violation an hour ago.
- [x] **H4 closed 2026-09-06: the Embedded size gate ADR 0009 cites now
      exists.** `check-embedded.sh` computed the byte count, printed it, and
      asserted nothing, so an artifact could double while the gate said OK and
      an Accepted ADR kept naming it as zero-cost evidence. It now compares
      against `scripts/embedded-size-baseline.txt`, pinned at **641,464 bytes**
      (measured, and reproducible to the byte — the artifact is deterministic
      for a fixed compiler and source).
      The pin names the compiler revision the script already requires
      unconditionally, so bumping the snapshot fails here first and forces a
      deliberate re-measure instead of a silently rebased number. The tolerance
      is **two-sided**: growth is the regression ADR 0009 cares about, and a
      shrink is either a real win worth recording or a sign the link did not
      produce the whole module — both want a human, not a stale baseline
      absorbing them. Note ADR 0011's recorded +8.1% identity-store cost would
      have tripped this, which is the point.
      Mutation-proven four ways: apparent growth, apparent shrink, a mismatched
      compiler revision, and a malformed baseline line each fail with a
      specific message.
- [x] **H2 closed 2026-09-06: ADR 0006's `~Copyable` hosts are now pinned by a
      compile-fail fixture.** The ADR promises "accidental sharing is a compile
      error" and nothing enforced it: `check-boundaries.sh` pinned `~Sendable`
      for four types and the ownership fixtures pinned `Terminal` (ADR 0010),
      but neither host type was covered. `Tests/Fixtures/Ownership/error.FrameHostMustNotBeCopied.swift`
      closes it, driven by the existing harness with `swiftc -c` — never
      `-typecheck`, since move-only enforcement runs in SIL.
      **Mutation-proven against the real defect**: deleting `: ~Copyable` from
      `Sources/GamaCore/FrameHost.swift:38` — the exact edit the audit named —
      makes the gate fail with "ownership negative compiled but must not", and
      restoring it returns green.
      Scope justified by measurement rather than assumed: `AppRuntime` needs no
      fixture because it stores a `HostPump`, which is itself `~Copyable`, and a
      `Copyable` struct cannot store a non-`Copyable` one ("stored property ...
      has non-Copyable type"). Dropping its annotation fails to compile on the
      spot. `FrameHost`'s stored properties are all `Copyable`, which is why it
      alone was reachable.
- [x] **H1 is closed — by a peer session, not by me, verified empirically
      2026-09-06 before I duplicated it.** `scripts/portable-global-state.py`
      exists (untracked in this checkout, so it is that session's work in
      flight), covers five portable targets rather than the audit's three, and
      its own docstring names "gap H1 of the unenforced-policy audit". I tested
      the audit's exact violation — a `nonisolated(unsafe)` global planted in
      `GamaPlugin` — and it fails with a precise message. The audit agent had
      read the tree before this landed. The same peer has extended my
      `scripts/package-graph.py` with a Swift-6-language-mode assertion, which
      is the ground their gate stands on, and has `scripts/evidence-locality.py`
      in flight for H5. **Left alone deliberately: not mine to commit.**
- [x] **Corrected a self-contradiction I introduced in the Packaged wasm site
      row.** It declared the 9,297,539-byte figure "removed rather than carried
      forward" and then restated the number three clauses later in the same
      cell. The historical clause no longer repeats it.
- [x] **The audit's other H5 instance is not reproducible.** It reported a
      stale 9,297,539-byte figure at `docs/Packaging.md:48`; that file contains
      no such figure and no `application/wasm` claim. Either it was fixed
      before I looked or the agent misread. Recorded rather than acted on.
- [x] **Remaining unenforced-policy backlog, from a full audit of ADRs, AGENTS.md,
      CONTRIBUTING.md and docs (15 gaps: 6 HIGH, 6 MEDIUM, 3 LOW).** The
      highest-leverage single fix is a `swift package dump-package` assertion
      gate, which would close three at once (H3 `strictLibrary` is hand-attached
      per target so a new shipped library escapes ADR 0012 silently; H6(b)
      nothing stops a shipped library gaining a package dependency, breaking the
      zero-runtime-dependency guarantee; L1 `Extern` scoping and the
      `NonisolatedNonsendingByDefault` ban are prose only) using output
      `check-docs.sh` already generates. Others worth naming: **H4** ADR 0009
      cites "the Embedded size gate not regressing" as evidence and **no size
      gate exists** — `check-embedded.sh` prints the byte count and asserts
      nothing; **H2** ADR 0006's `~Copyable` on `FrameHost`/`AppRuntime` has no
      pin, so deleting `: ~Copyable` would pass every gate; **H1** the
      no-process-global rule is three string literals wide, so a
      `nonisolated(unsafe) static var` in `GamaPlugin` passes; **H5** the
      evidence policy is enforced in one file, and `docs/Packaging.md:48` still
      carries the 9,297,539-byte figure the ledger removed as stale.
      **Status 2026-09-06: H3, H6(b), L1, H4 and H2 are closed by the gates and
      fixture recorded above; H1 and H5 are closed below. No HIGH gap remains
      open.**

- [x] **Re-derived 2026-09-06, because the MEDIUM/LOW half was never written
      down.** Across `tasks/` and `docs/` the only identifiers ever named were
      `L1` (closed by the package-graph gate) and `M2`; the other seven existed
      solely as the count "6 MEDIUM, 3 LOW" above. So this is a fresh pass over
      the ten Accepted ADRs rather than a box-ticking exercise, and it replaces
      that number with an inventory. Two gaps found and closed, three recorded
      open with their reasons.

      **Closed — ADR 0012's second half was unasserted.** The record pairs
      strict memory safety with "explicit import access levels everywhere", and
      `scripts/package-graph.py` checked only the first.
      `ExistentialAny`, `MemberImportVisibility`, and `InternalImportsByDefault`
      live in `Package.swift`'s `strictCore`, which every Swift target takes
      directly or through `strictLibrary`, so a target assembling its own
      settings list keeps one promise and drops the other silently. Now
      required on every Swift target, in the same place and shape as the
      language-mode rule. **Mutation-proven in the realistic shape**: a
      hand-rolled list on `GamaPlugin` that keeps `.strictMemorySafety()` and
      the error promotion — so the pre-existing checks all pass — fails naming
      the three absent features. Baseline before the change: 0 of 21 Swift
      targets missing any of the three.

      **Closed — ADR 0008's stated reason for the pump's location was not
      asserted.** The record says the pump *policy* stays in
      `Sources/GamaCore/HostPump.swift` precisely because
      `scripts/check-embedded.sh` compiles GamaCore alone, so a pump in
      GamaDraw would sit outside the Embedded proof. Nothing checked it: moving
      that file would have kept every gate green while quietly removing the
      pump from the only Embedded evidence there is. `check-embedded.sh` now
      requires the file, rejects a `HostPump.swift` appearing in GamaDraw, and
      — the part that makes the first two mean something — asserts the file was
      actually collected into the compile it performs.
      **Mutation-proven**: moving `Sources/GamaCore/HostPump.swift` away fails
      with the ADR named. The `GamaDraw/HostPump+CellBuffer.swift` half is
      deliberately *not* covered; that is the `CellBuffer` side and belongs
      there, since GamaDraw cannot be Embedded. Stated limit: the GamaDraw
      half of the check matches the exact name `HostPump.swift`, so a policy
      file arriving there under another name would slip past; the positive
      assertion (the file exists in GamaCore *and* was collected into the
      compile) is the half that actually carries the guarantee.

      **Closed — ADR 0005's wire format golden payload.**
      `DrawListTests.v1GoldenPayloadPinsMagicVersionAndFieldOrder` encodes a
      two-command list through the shipped `DrawList.encode()` and compares it
      to little-endian bytes laid out from the ADR (magic `GAMA`, version 1,
      fill then text field order), then decodes those same bytes. The expected
      array is not a copy of a prior encode() dump. Filter
      `--filter DrawListTests` ran 8 tests including this one.

      **Open — ADR 0001's "no backend forks layout, paint order, or the dirty
      gate" has no mechanical form.** `check-boundaries.sh` polices imports and
      ownership, which is adjacent but different. A backend calling
      `LayoutEngine` with its own policy would pass everything. Recording it as
      genuinely hard rather than pretending a grep covers it; the honest
      candidate is a per-backend golden `DrawList` for one shared scene, which
      is again test authoring.

      **Open — the `docs/` half of the original audit was never re-derived
      here.** This pass covered the ten Accepted ADRs. `AGENTS.md`,
      `CONTRIBUTING.md`, and the prose in `docs/` have not been swept for
      asserted-but-unenforced policy in this slice, and claiming otherwise
      would repeat the "nine gaps" fiction this bullet replaced.

- [x] **H1 closed 2026-09-06, and measurement made the rule much smaller than
      the audit assumed.** `check-boundaries.sh` policed process-global state
      with three string literals — `ActionRegistry`, `Invalidator.shared`,
      `nonisolated(unsafe).*_host` — so a global named anything else passed.
      The obvious fix was a stored-versus-computed `static var` heuristic.
      Measured against the pinned compiler first, that turned out to be
      unnecessary: every target builds in Swift 6 language mode, which rejects
      the common case by itself — planting `static var probeCounter = 0` in
      `GamaPlugin` fails with "static property 'probeCounter' is not
      concurrency-safe because it is nonisolated global shared mutable state".
      The compiler is self-enforcing here exactly as ADR 0006's `AppRuntime`
      turned out to be, so `Scene.swift:428`'s computed `static var` never
      needed distinguishing.
      What the compiler still accepts, both verified to build clean with zero
      errors, are the two deliberate hatches: `nonisolated(unsafe) static var`
      and `@MainActor static var`. `scripts/portable-global-state.py`, chained
      from `check-boundaries.sh`, rejects both across `GamaCore`, `GamaPlugin`,
      `GamaDraw`, `GamaEmbed`, and `GamaMLIR` — an **extension** of the old
      three-target scope, justified because `GamaDraw` and `GamaMLIR` are
      equally platform-free. Backends stay out: `GamaWASM/WASMHost.swift:89`
      is a justified single-threaded use and would fail.
      **Mutation-proven against the exact line the audit named**: with
      `nonisolated(unsafe) static var probeCounter = 0` in `GamaPlugin` the old
      three-literal rule still passes and the new gate exits 1 naming the file
      and line; same for the `@MainActor` form; removing them returns 0.
      The self-test pins the non-obvious half — that a *mention* is not a use,
      so the doc comment at `WASMHost.swift:87` and a string literal quoting
      the attribute both stay green, while a trailing `// justified` comment
      does not launder a real declaration on the same line.
      Two deliberate over-reaches, both green today and both fail-closed. The
      global-actor pattern is `@[A-Z]\w*Actor\b`, which matches any attribute
      ending in `Actor` rather than only real global actors. And the
      comment/string walk is line-scoped, so rather than let it misread a
      multi-line `"""` literal's interior as code the script refuses any file
      containing one; none exists in these targets, and one appearing is a
      reason to write a real lexer, not to trust this walk. An earlier draft of
      that docstring claimed the multi-line case "fails closed" on its own,
      which was false — the refusal is what makes the claim true.
      Two things stated rather than papered over. The global-actor ban is one
      step wider than "no global state" (it rejects the attribute on a function
      too), on the ground that isolation couples a portable target to a
      concurrency runtime it must not require; only `GamaCore` is compiled by
      `check-embedded.sh`, so for the other four this gate is the only thing
      saying so. And a `static let` bound to a reference type with mutable
      interior is process-global state that neither the compiler nor this
      script rejects; none exists in these targets today (every `static let` is
      a value-type constant) and catching it needs type information, not text.
      Green locally: `check-boundaries.sh`, `check-docs.sh`,
      `check-doc-coverage.sh`, all exit 0. Local evidence only.

- [x] **Closed 2026-09-06: the compiler half of H1 is now asserted.**
      `scripts/portable-global-state.py` is only the smaller rule because Swift
      6 language mode rejects the common case, and nothing gated that mode.
      `scripts/package-graph.py` now requires it on **every Swift target**, not
      only shipped ones: an executable or the test target dropping to Swift 5
      reopens bare mutable globals just as quietly. `swiftLanguageVersions` is
      unset package-wide, so the mode is hand-attached per target exactly like
      the strict-memory-safety settings that script already policed.
      **The mutation test caught a real defect in the first draft of this
      gate, and the defect was the very false green the gate exists to
      prevent.** Planting `strictLibrary + [.swiftLanguageMode(.v5)]` on
      `GamaPlugin` dumps as `[{"_0": "6"}, {"_0": "5"}]` — SwiftPM appends
      rather than replaces — and the *last* declaration wins at compile time.
      Verified at the compiler, not inferred: with that manifest a bare
      `static var probeCounter = 0` in `GamaPlugin` builds with **zero**
      concurrency errors, where the unmutated package rejects it. The
      first-match accessor read `'6'` off that manifest and passed. It now
      collects every declared mode and fails if any is not `6`, so the
      duplicate-declaration shape fails with both values named. Self-test pins
      the `["6", "5"]` case specifically.
      Green locally: `check-package-graph.sh`, `check-boundaries.sh`,
      `check-docs.sh`, `check-doc-coverage.sh`, `check-evidence-freshness.sh`,
      all exit 0. `Package.swift` and `Sources/` restored byte-identical after
      every mutation. Local evidence only.

- [x] **H5 closed 2026-09-06: anchored evidence claims are now confined to the
      one file that is checked for staleness.** Two halves. The live defect:
      `docs/Packaging.md:48` held a second, hand-maintained copy of the
      packaged-wasm evidence — anchored to `77812d99`, naming Pages run
      `33919361438` and the 9,297,539-byte artifact. Measured, not inferred:
      both copies were written together by `8bb838b` on 2026-09-04; the ledger
      retired that figure as stale in `a4c7a5c` on 2026-09-06 15:36, because
      both `scripts/bundle-web.sh` and the wasm source it bundles had changed;
      `docs/Packaging.md` was still asserting it under two hours later when
      this gate landed. The duplicate stood for two days, the divergence for
      about two hours, and nothing would have caught either. That
      cell now points at the `Packaged wasm site` row of `Capabilities.md`
      instead of restating it, which is the ledger's own "update once and link"
      rule applied. The structural half: `scripts/evidence-locality.py`, chained
      from `check-docs.sh`, fails an anchored evidence claim or a CI run id in
      any document other than the ledger, because
      `scripts/evidence-freshness.py` reaches exactly one file
      (`LEDGER = "docs/Capabilities.md"`) and everything else could go stale in
      silence with every gate green — which is precisely what happened.
      **Mutation-proven against the real historical defect**: restoring the
      exact retired `docs/Packaging.md` cell makes the gate fail with both
      messages and exit 1; removing it returns exit 0. The self-test asserts
      both directions, including that measurement conditions are *not* claims,
      so `docs/Performance.md` naming the commits a benchmark ran at and
      `docs/Toolchain.md` naming a compiler revision stay untouched. A sweep of
      `docs/` plus the four root documents found no other instance. Green
      locally: `check-docs.sh`, `check-doc-coverage.sh`,
      `check-evidence-freshness.sh`, `check-boundaries.sh`, all exit 0. Local
      evidence only; no hosted run has seen this.

- [x] **Closed 2026-09-06 by `a69566a`, in another session.** The
      `Packaged wasm site` cell said the 9,297,539-byte figure was "removed
      rather than carried forward" and then carried it forward in the same cell
      as "historical detail". It now states the byte count is deliberately not
      repeated, and names the earlier revision's contradiction as the reason.
      The one surviving mention is the clause declaring the figure retired,
      which is what a retirement notice has to name. Recording the general
      lesson, because no gate covers it: freshness passes here because the
      anchor is fresh, and staleness of a *number inside* a row is not
      something an anchor can express.

- [x] **Closed 2026-09-06. A ledger entry could describe a script the commit
      did not contain, and nothing caught it.** Observed on this very file:
      `a69566a` committed the
      H1 and H5 bullets — which name `scripts/evidence-locality.py` and
      `scripts/portable-global-state.py`, and say they are chained from
      `check-docs.sh` and `check-boundaries.sh` — while both scripts and both
      chain lines were still uncommitted in the working tree. At that commit
      the documentation asserts two gates that do not exist in it, and every
      gate stays green, because nothing checks that a path named in
      `tasks/` or `docs/` is present. The same shape would let a `docs/`
      reference to a deleted script survive indefinitely.
      Note this is the *inverse* of the drift `check-evidence-freshness.sh`
      catches: that gate asks whether a claim's sources have moved since it was
      proven, not whether the thing a claim names exists at all.
      `scripts/referenced-paths.py`, chained from `check-docs.sh`, now fails
      any document naming a repository path the tree does not contain.
      **Mutation-proven by reproducing the real split state**: moving both
      scripts out of `scripts/` makes it report all 11 references across
      `tasks/goals.md`, `tasks/todo.md`, and `CLAUDE.md` and exit 1, while
      `check-evidence-freshness.sh` run against the same tree exits 0 — the
      blindness measured, not asserted.
      **Scope was set by measurement and is deliberately narrow.** A first pass
      over every backticked filename reported 121 broken references that were
      nothing of the kind: prose naming a file by bare name (`FrameHost.swift`)
      or by a module-relative fragment (`GamaCore/HostPump.swift`). That is how
      people write, and failing it would have forced 121 edits to buy nothing.
      Only a **root-anchored** path counts as a claim, which cut the false set
      from 121 to 7. All 7 remaining were in `docs/superpowers/plans/` and
      `docs/superpowers/specs/drafts/`, naming files those documents propose to
      create; CLAUDE.md defines drafts as open questions and neither tree as a
      capability claim, so both are excluded. Accepted specs are **not**
      excluded: an accepted design naming a missing path is the defect this
      gate is for. Baseline after the exclusions: 322 claims across 56
      documents, zero broken.
      Green locally: `check-docs.sh`, `check-boundaries.sh`,
      `check-doc-coverage.sh`, `check-evidence-freshness.sh`,
      `check-package-graph.sh`, all exit 0. Local evidence only.

## Acceptance-matrix drift (observed 2026-09-06 17:1x, local `main` `8c9d1c7`)

Two `CLAUDE.md` statements no longer match `scripts/check.sh`. Recorded here
rather than edited because that file is dirty under a concurrent session, and
because this command's scope is the ledger.

- [x] `CLAUDE.md:86` says the `gates=(…)` array is "thirteen entries at time of
      writing". It is **fifteen**: the thirteen plus `check-evidence-freshness.sh`
      and `check-package-graph.sh`. The surrounding sentence already tells the
      reader the array is the authority, so the prose is self-protecting, but
      the number is wrong.
- [x] The in-flight `CLAUDE.md` paragraph describes `check-evidence-freshness.sh`
      as "a **third** script outside the array … unwired on purpose", with the
      remaining step being "adding it to `gates=(…)`". Commit `67377af`
      ("enable evidence freshness as the fourteenth gate") already did that, so
      the paragraph is stale on landing. It does hedge — it tells the reader to
      check `git status` and re-run rather than trust either state — so this is
      staleness, not a false claim.

Both are for whoever owns `CLAUDE.md` next; re-read the array before fixing
either, since the count moved twice today.

## Source review and two answered residuals (2026-09-06 22:0x)

- [x] **Both `CLAUDE.md` items directly above are now fixed, not just recorded.**
      The file states the array is fifteen entries and says the count moved from
      thirteen the same day, and the stale "third script outside the array"
      paragraph is gone. It also now records something previously undocumented:
      `CLAUDE.md` is itself scanned by `scripts/referenced-paths.py` and
      `scripts/evidence-locality.py`, so editing it can break `check-docs.sh` —
      the four root documents are in both scanners' scope.

- [x] **ADR 0001's residual is ANSWERED, and the answer is that the recorded
      candidate does not work.** The bullet above proposed "a per-backend golden
      `DrawList` for one shared scene". That is unsound: there is no shared grid,
      so there is no shared value. Embed's extent is the `columns`/`rows` passed
      to `makeContext`; `GamaAppleUI`'s is derived from a measured monospaced
      cell size in `Sources/GamaAppleUI/GamaHostView.swift` and re-forced every
      frame, so a test cannot pin it by sending `.resize`. N goldens therefore
      differ by construction, and each is a recording of its own backend — when a
      backend forks, its golden is re-baselined and the gate rubber-stamps the
      fork. That is the green-by-construction family this repository already
      documents.
      A reshaped form IS sound: ONE reference derivation plus cross-backend
      equality, with the expected extent computed independently of the backend
      and asserted before the commands are compared. Reachable for exactly two
      backends — `GamaEmbed` and `GamaAppleUI` under `canImport(AppKit)`.
      `GamaWASM` is not reachable (`WASMHostBox`, the pump and `frame()` are all
      inside `#if arch(wasm32)`), `GamaTUI` is `CellPresenter`-family and never
      builds a `DrawList`, and `GamaMLIR` lowers `RenderNode` to text so it is
      outside the family. **Designed, not implemented**; no gate is claimed.
      Two limits stated rather than papered over: a fork of the *dirty gate*
      produces byte-identical output and stays invisible, and
      `TUIRenderer`/`StreamRenderer` bypass `HostPump.advance(into:emit:)`
      entirely, so `HostPump+CellBuffer.swift`'s "four backends" comment is
      currently overstated.

- [x] **The `docs/` half of the unenforced-policy audit is now derived.** Ten
      gaps: 1 HIGH, 6 MEDIUM, 3 LOW, plus two recorded as not mechanizable with
      reasons, and one category (force-push, PR-only, merge-after-green) that is
      enforced by the GitHub ruleset rather than by anything in the repository.
      One is a LIVE error rather than a latent risk:
      `docs/TerminalOwnershipMigration.md:21` cites the Windows `Terminal`
      declaration at line 493; measured, it is at 497, and 493 is a doc comment.
      `scripts/referenced-paths.py` is green on it **by construction** — it
      matches `path:<line>` and then discards the suffix, so it proves the file
      exists and never that the line means what the prose says. Cheap partial
      fix available: where a citation carries `:NN`, require the file to have at
      least NN lines. A full check is not possible and should not be claimed.
      Stated so a later pass does not repeat it: a count-marker gate must exempt
      dated evidence reports, or it will fail honest history — `docs/Swift65SDK27.md`
      says thirteen gates because that is what its dated run measured.

- [x] **Full local gate audit at this tree.** Twelve of the fifteen gates ran and
      all exited 0, read directly rather than through a pipe: apple,
      apple-platforms, boundaries, concurrency-negative, c-abi, embedded, linux,
      wasm, docs, doc-coverage, evidence-freshness, package-graph. **317 tests in
      56 suites.** Three did not run and fail closed on genuinely missing local
      prerequisites, not on defects: `check-android.sh` (no `ANDROID_NDK_HOME`),
      `check-android-emulator.sh` (no `ANDROID_HOME`, and no booted emulator),
      `check-mlir.sh` (no `mlir-opt`). Local evidence only.

- [x] **The docs sweep's one HIGH gap is closed: the platform-import ban now
      covers every portable target.** `check-boundaries.sh` banned Foundation,
      AppKit, UIKit, Darwin, Glibc, WinSDK, and Synchronization in `GamaCore` and
      `GamaPlugin` only, while `scripts/portable-global-state.py` policed global
      state across five targets. The two rules answer the same question — may
      this target require a platform or concurrency runtime — so the mismatch
      left `GamaDraw`, `GamaEmbed`, and `GamaMLIR` forbidden a
      `nonisolated(unsafe)` global yet free to `import Foundation`, which would
      have taken the platform dependency the global was banned for.
      The ban now uses the same five-target list, and both the list and the
      reason are stated beside it so they cannot drift apart silently.
      **Green by measurement, not by hope**: all three newly covered targets
      import only `GamaCore` (and `GamaDraw` in `GamaEmbed`'s case) today, so the
      extension was verified clean before it was made.
      **Mutation-proven in both directions**: `import Foundation` planted at the
      top of `Sources/GamaDraw/CellSerializer.swift` makes the gate exit 1 and
      name the file and line; restoring the file byte-identically returns exit 0.
      The pre-change target list was re-read from `HEAD` to confirm it names only
      the two targets and would have passed that same mutation.
      Gates green after the change: boundaries, docs, doc-coverage,
      evidence-freshness, package-graph, all exit 0. `check-apple.sh` was not
      re-run because this slice changes no Swift source. Local evidence only.

- [x] **All four source defects are FIXED and merged into `origin/main`
      at `bd727e9` (PRs #89 and #90).** Hosted six-job Gama acceptance run
      `34081434868` concluded success on that SHA; Pages run `34081434925`
      deployed. Eleven runnable gates had exited 0 on the merged tree, and
      the suite was **321 tests in 56 suites** (317 before, +3 TextField
      space, +3 layout, −2 duplicate cases). Embedded 643,432 bytes, +0.31%
      on the 641,464 pin. This integration is hosted proven, not local-only.

- [x] **Residuals from this pass, each real and none of them fixed.** Recorded
      rather than quietly dropped. **Partly closed 2026-09-08: (1) and (5) are
      fixed; (2), (3) and (4) are still open and are re-listed as their own
      boxes below, so this box being checked does not mean the pass is clean.**
      (1) **The fail-open `if grep --include` shape survives in two more places,
      and the larger one was missed by my own review.** `scripts/check-boundaries.sh`
      still greps a nonexistent-directory-tolerant pattern for the three
      process-global literals over three directories, and for the
      `GamaPlatformServices` inverse ban over **thirteen** — that second one is
      the biggest remaining exposure by target count and fails silently exactly
      as the import ban did. The `TerminalRescue.swift` check is a milder case:
      no `--include`, so a missing file exits 2 with a diagnostic — fail-open but
      noisy, not silent.
      (2) **`flexPriority` is now advisory.** The public property still collapses
      both axes and is no longer what the layout solver consults; an internal
      `flexPriority(along:)` in `Sources/GamaCore/RenderNode.swift` is. Its doc
      comment says so. Needs a decision record to deprecate it or promote the
      axis-aware form to public — deliberately not decided, because that is a
      public API change.
      (3) **The WASM no-host path has zero coverage in either export tier.**
      Nothing anywhere asserts `-1`, and the state is reachable:
      `Sources/GamaWASM/WASMHost.swift` documents that a first install throwing
      `SceneConfigurationError` leaves no host installed. Closing it needs a
      fixture app whose `install` throws, plus changes to the Node smoke driver.
      Note the `-2` defect just fixed was established by source inspection, not
      measurement — probing the pre-fix build traps with a signature mismatch on
      exactly the discriminating key codes.
      (4) **No regression test pins a `complete` issued from `connect`.** The
      corrected `docs/backends/TUI.md` example is correct by construction; the
      existing test only pins that `connect` fires at all.
      (5) `CONTRIBUTING.md` still calls the boundary gate "GamaCore import bans"
      when it has covered five targets since 2026-09-06.

## Fail-open boundary scans and two carried residuals (2026-09-08)

- [x] **Closed residual (1): the fail-open `if grep … <paths>` shape.**
      `scripts/check-boundaries.sh` now defines `require_paths` and asserts
      every scanned path before the grep, at all three sites — the three
      process-global literals, the `GamaPlatformServices` inverse ban over
      thirteen targets, and the single-file `TerminalRescue.swift` check.
      Measured rather than argued, because the mechanism was easy to get wrong:
      with a target renamed and a real `import GamaPlatformServices` planted in
      the renamed directory, the unguarded grep exits 0 and the gate **passes**;
      the guarded form exits 1 and names the missing path. Note the exposure is
      narrower than the original bullet implied — a violation that coexists with
      a missing directory is still caught, because BSD grep exits 0 when it
      matches anywhere. What was lost was the renamed target being scanned at
      all. `./scripts/check-boundaries.sh` exits 0 after the change.
- [x] **Closed residual (5):** `CONTRIBUTING.md` called the boundary gate
      "GamaCore import bans"; it now says all five portable targets.
- [ ] **Carried residual (2): `flexPriority` is advisory.** The public property
      collapses both axes and is not what the solver consults; the internal
      `flexPriority(along:)` in `Sources/GamaCore/RenderNode.swift` is. Still
      needs a decision record to deprecate it or promote the axis-aware form —
      deliberately not decided here, because it is a public API change.
- [x] **Carried residual (3): the WASM no-host path has no coverage in either
      export tier.** Closed 2026-09-08 on this same branch by `99890ed`:
      `Tests/Fixtures/WASMFailedInstall/main.swift` is an app whose `install`
      throws, `check-wasm.sh` builds it, and `wasm-runtime-smoke.mjs` asserts
      the `-1` no-host result in both export tiers. Proven hosted, not only
      written: the WebAssembly job passed on that commit. Recorded here after
      review pointed out the box was still open one commit after it closed.
- [x] **Carried residual (4): no regression test pins a `complete` issued from
      `connect`.** Closed 2026-09-08: `completionFromConnectEndsTheRun` in
      `Tests/gamaTests/StreamOutputTests.swift` mirrors the documented example
      and pins the status reaching `AppRuntime.completion`, that an input-less
      stream run ends on its own, and that exactly one frame reaches the
      renderer. Regression, not merely passing: with
      `app.connect(subscriptions)` disabled it fails at its first assertion.
      A first mutation attempt applied nothing (BSD `sed` ignores `\s`) and
      reported a pass; the recorded run asserts the substitution took first.

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
