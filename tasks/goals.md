# Goals

## Ship the Swift 6.4 Gama Framework

status: done

- Apple Swift 6.4 debug, 73 tests, release, and iOS/tvOS/visionOS compile:
  locally green.
- Portable core, macros, drawing, TUI, Apple UI, C ABI, WASM, MLIR, and Qt
  adapter sources: implemented; Qt 6.11 and MLIR parser gates are locally green.
- Exact 2026-08-14 Swift 6.4 snapshot and matching Linux, WASM, and Android
  SDKs: checksum-pinned and locally installed; Linux, WASM runtime, Android
  arm64/x86_64 cross-build, JNI packaging, API 36 emulator input/frame round
  trip, and Embedded compile/link gates pass.
- Hosted Linux, Windows, WASM, Android/emulator, and required PR checks: pending.
- Merge is forbidden until the required matrix is green.
- Outcome: merged as PR #6; hosted "Gama acceptance" matrix green on main at
  f509e2c (2026-08-24). Superseded going forward by the umbrella goal below
  (6.5-dev snapshot, Qt adapter removed 2026-08-26).

## Merge all branches into main locally

status: done

- Verified 2026-08-26: every branch's content is already contained in main;
  zero merge commits were needed. All remote branches
  (feat/swift-65-dev-umbrella, pr/tui-embedded-core, swift-refactor-c4c7b,
  winsdk-wrapper-94d76) are ancestors of main (`git branch -a --merged main`).
  Local feat/tui-embedded-core (39f1b35) is tree-identical to the already
  merged origin/pr/tui-embedded-core (e79b279); local
  pre-remote-main-20260824 (154ff82) differs only by an obsolete
  .swift-version pin (2026-08-11, superseded by main's 2026-08-21). Both
  local branches share no merge base with main (pre-remote history); merging
  them literally would have deleted ~9k lines of the current framework, so
  they were left as historical snapshots, not merged.
- Branch cleanup 2026-08-26 (late evening, Donald's explicit instruction):
  after PRs #8 and #9 merged, deleted every branch except main, remote and
  local. Verified before deleting: six tips ancestors of main
  (docs/claude-md-operational-guide 610c06c, docs/toolchain-accuracy-sweep
  a52a273, feat/swift-65-dev-umbrella a1aa305, pr/tui-embedded-core e79b279,
  swift-refactor-c4c7b 98e7c59, winsdk-wrapper-94d76 74f2648);
  feat/tui-embedded-core 39f1b35 tree-identical to merged e79b279; the
  historical snapshot pre-remote-main-20260824 154ff82 deleted on explicit
  instruction, SHA recorded here for recovery (objects persist; gc is
  forbidden in this tree). Honest residual: PR #9 was merged while its
  matrix was still running (WASM + Embedded green at cleanup time, four
  jobs in progress); Autofix watches for post-merge failures.

## Build the Gama umbrella application framework

status: in_progress

- Intention (Donald, 2026-08-26): a cross-platform, macro/plugin-based
  UI/UX/application framework in Swift — Tauri/React-Native-class — spanning
  WASM, Windows, macOS desktop, Embedded, and more, with the retained-IR
  renderer as the foundation (own-the-rendering decision).
- Sub-project 1 (foundation) Current: DONE. Canonical checkout adopted at
  ~/Desktop/Gama on the donaldfilimon/gama history; migrated to swiftly
  main-snapshot-2026-08-21 (Swift 6.5-dev); Qt adapter removed; all eight
  local gates green; full hosted matrix green (Linux/macOS/WASM/Embedded/
  Android on 6.5-dev, Windows on 6.4.x — see exception below); merged as
  PR #7 (74e77df on main, 61 commits); dev/active/gama-swift retired to
  dev/archive/gama-swift-superseded-2026-08-26 after verifying zero unique
  commits/stashes; ~/CLAUDE.md corrected.
- Windows exception (Current, honest residual): swift.org has published no
  Windows main-development snapshot since 2026-05-20-a, so the Windows job
  runs the proven 6.4.x 2026-08-14-a installer. Windows is NOT yet verified
  on 6.5-dev; revisit when swift.org resumes Windows main snapshots.
  Re-verified 2026-08-26 (late evening): swift.org's newest Windows
  main-development snapshot is still 2026-05-20-a — blocker stands.
- Verification 2026-08-26 (evening): `swiftly run swift build` and
  `swift test` (scratch path /private/tmp/gama-framework-swiftpm) green on the
  pinned main-snapshot-2026-08-21 — 74 tests (56 XCTest + 18 Swift Testing),
  0 failures (superseded 2026-08-27: the suite is Swift Testing only now,
  92+ tests — see the Swift Testing bullet below); `check-docs.sh` zero-warning gate green. CLAUDE.md expanded into
  the full operational guide and opened as PR #8
  (docs/claude-md-operational-guide branch).
- Post-merge matrix for PR #9 (toolchain-accuracy sweep): Android emulator
  job failed once with an adb "Broken pipe" APK-install infra flake
  (PR #9's CI changes were cosmetic renames, nowhere near the Android
  path); rerun succeeded 2026-08-26 22:19 — matrix fully green on main.
- DocC member coverage (2026-08-26 evening, goal-loop session): GamaCore
  (all ten files), GamaTUI, and GamaAppleUI now have zero undocumented
  public declarations — four comments-only commits (782 insertions, 0
  deletions), each verified by check-docs.sh (slice 4 also by a full pinned
  swift build), authored in worktree /private/tmp/gama-docc-wt. Open as
  PR #10; merge only when its matrix is green.
- Modern-Swift practices sweep (started 2026-08-27, Donald's request via
  /plan then /goal continue): three parallel audits of the whole package
  (portable core; backends; tests/macros/build config) produced a ranked
  modernization backlog — granular checklist under "Modern-Swift sweep" in
  tasks/todo.md. Executing in small gated slices on a topic branch; PR #10
  (DocC member coverage) must merge first for GamaCore/TUI/AppleUI files
  (its Android emulator job flaked with the same adb-offline infra failure
  as PR #9; rerun started 2026-08-27 ~00:15).
- Swift Testing globally (Donald, 2026-08-27): every XCTest suite moved to
  Swift Testing. Macro expansion uses SwiftSyntaxMacrosGenericTestSupport
  (no XCTest). Invocation is `swiftly run`. Pin-consistency gate added.
  `ZStack(.topLeading)` no longer flattens into parent stacks (group
  sentinel). Docs expanded: `docs/Testing.md`, `docs/Toolchain.md`,
  Capabilities remaining-column honesty, GamaCore DocC Testing article.
  Do not mark this umbrella goal done; sub-projects 2–4 remain Proposed.
- Swiftly-run convention (Donald, 2026-08-27): agents run the codebase
  with `unset TOOLCHAINS` then `swiftly run swift <build|run|test|…>`.
  Recorded in AGENTS.md, CLAUDE.md, README.md, docs/Toolchain.md.
- Codex P1s (2026-08-27): natural-size border titles paint; HStack 1×1
  Divider is vertical; TextField drops C0/DEL; U+231A is two cells; focus
  wrap wins over custom label colors. Umbrella stays in_progress.
- Dialect validation (2026-08-27, writing-skills session): six fresh-agent
  baseline scenarios (typed-throws decoder, ~Copyable handle, embedded-safe
  core, XCTest-free macro tests, C-ABI error surface, no-imports Signal)
  all reproduced the repo's modern-Swift dialect unprompted — a dedicated
  "modern Swift 6.5" skill is unwarranted (no failing baseline; recorded in
  session memory). Reusable finding: the baseline Signal design is the
  leading Slice C candidate (see tasks/todo.md).
- Integration repair (2026-08-27): merging the DocC branch after PR #11
  resolved three source conflicts in favor of stale declarations, removing
  RenderNode.group, the Hashable conformances, and the noncopyable
  host/runtime declarations — main was non-compiling with a red acceptance
  matrix, and PRs #10/#13 were merged while red (honest residual; the
  green-matrix rule was violated). Repaired by PR #14 (fix/restore-sweep-
  semantics, merged 5c27a32 on a fully green six-job matrix), which also
  fixed the actual Linux failure inherited from PR #11
  (Foundation-only components(separatedBy:) in WASMSerializerTests) and
  the stale ZStack/TupleView flattening prose. Duplicate repair PR #15
  closed unmerged; its unique Hashable compile test folded into the docs
  overhaul PR.
- Scene-first core (2026-08-27): the approved app-shell design is implemented
  on `feat/scene-first-core` as the second delivery slice. The source-breaking
  `App.content` migration, explicit primary-scene validation, typed group
  payloads/actions, lifecycle events, non-generic closure-backed `FrameHost`,
  single-surface backend migration, and Embedded-safe payload erasure are
  locally proven on the consolidation tree: pinned Apple debug/release plus
  113 Swift Testing cases in 31 suites, iOS/tvOS/visionOS compile, boundaries,
  zero-undocumented-public-API DocC, C ABI, Embedded, Linux SDK, WASM
  browser/runtime, Android cross-build plus emulator input/frame round trip,
  and MLIR gates are green. Hosted PR and post-merge matrices remain separate
  acceptance evidence and must be green before this slice is complete.
- Docs overhaul (2026-08-27, Donald's /plan approved): executed in six
  phases on docs/claim-honesty — claim-honesty (gama.group now test-
  proven; Capabilities status vocabulary; non-tautological check-docs
  grep; Testing.md file map), GamaCore DocC sweep alignment (noncopyable
  hosts guidance, group-vs-overlay, Topics curation), zero undocumented
  public declarations package-wide, backend guides + CONTRIBUTING + MLIR
  dialect reference + docs index + ADRs 0001-0007, and the deterministic
  check-doc-coverage.sh gate wired into check.sh and CI (empty
  allowlist). Outcome: merged as PR #16 (acc2f88) 2026-08-27 06:11Z on a
  fully green six-job PR matrix (green-before-merge honored); post-merge
  main acceptance run 33044975550 also completed successfully.
- Consolidation finalized (2026-08-27, Donald's "merge all branches into
  main and delete old"): every branch's content is in main — scene-first
  core + backend DocC catalogs + ledger sync via PR #19; my completion
  work (test-migration stragglers and scene-surface docs) landed
  independently on main before PR #20 could carry it, so #20 reduced to
  the doc-coverage count-dedup fix plus PR #18's surviving docs delta.
  Deleted after containment verification (ancestor or patch-equivalent):
  remote+local docs/docc-member-coverage, fix/zstack-topleading-flatten,
  fix/restore-modern-sweep-merge, feat/scene-first-core (PR #18 closed,
  delta folded into #20), chore/swift-65-dev-refresh,
  abbey/consolidate-gama-branches, plus five stale /private/tmp
  worktrees. Post-#16 main acceptance: completed green. Honest residuals:
  PR #19 was merged while its PR matrix was incomplete (pattern repeat),
  and PR #20's auto-merge fired instantly because branch protection
  requires PRs but does NOT mark the six acceptance jobs as required
  status checks — auto-merge only waits on required checks. Marking
  those jobs required is the settings fix (Donald's call). Post-#19 and
  post-#20 main runs pending at ledger time — Current only when they
  land green. Remaining branches: main and feat/apple-multiwindow-shell
  (Remote Control session's active sub-project 3 slice 2).
- Session close (2026-08-29, main at 2b87887). Six merges landed from two
  concurrent sessions: PR #60 + #64 (MLIR emitter unification, Roadmap item 9,
  implemented by a peer session — a local duplicate implementation was compared
  point-by-point and abandoned as redundant; the peer's had 18 fixtures against
  12, covered all 14 RenderNode cases on both entry points, caught a fifth
  MLIRDialect.md error, and had hosted proof), PR #61 (an intermittent NSFont
  crash in GamaHostView — styledFont built a font per text command per frame,
  aborting inside CTLineCreateWithAttributedString; 14 of 15 harness runs
  aborted before the fix), PR #62 (Terminal ~Copyable + ADR 0010 + the four
  master-plan:364 artifacts), PR #63 (Apple-host profiling baseline and the
  harness that found the crash).
  Two honest limits recorded with PR #63 rather than papered over: Instruments
  Allocations deadlocks in liboainject before main on this machine, so Task 5's
  "allocations within 5%" criterion is currently UNEVALUABLE here and no numbers
  were invented; and draw(_:) ignores its dirtyRect, so "dirty-rect handling"
  has no distinct measurable path today.
  A measurement-discipline correction worth keeping: this session claimed its
  MLIR refactor moved "exactly one fixture expectation" and treated that as
  tight discipline. It was a COVERAGE ARTIFACT — the local suite had no laid
  flexFrame fixture, so it could not see that the laid flex frame reorders too.
  Two is the correct count. One is what a less sensitive instrument reports.
- **View-state identity — a measured correctness defect that NO ledger item
  tracks.** Recorded here because a checkbox scan of tasks/todo.md cannot see
  it: `git grep -i 'view-state\|state identity'` across tasks/ returns zero
  hits. Scene content is a closure the host re-evaluates every render
  (Sources/GamaCore/Scene.swift:211-214), and @Reactive stores its Signal in the
  component instance, so a component constructed inline gets fresh signals every
  frame. A press mutates an instance discarded before paint: measured
  2026-08-27, the action reports it ran while the painted frame still reads
  `count 0`. Pointer presses lose state identically. There is no diagnostic, no
  warning, and no failing test — the control just looks inert. The only
  mitigation is prose telling authors to hoist, which is itself incomplete
  because hoisting stores state per scene declaration, so every window of a
  WindowGroup shares one instance.
  Design approved and specced 2026-08-29:
  docs/superpowers/specs/2026-08-29-view-state-identity-design.md (host-owned
  state keyed by (NodeID, slot), staged diagnostic → store → .stateScope).
  Implementation NOT started. Until it is, this remains the most serious known
  correctness gap in the framework, and it is invisible to the box scan.
- Sub-projects 2 and 4 remain Proposed drafts under
  docs/superpowers/specs/drafts/ (plugin runtime + capability model; packaging
  & distribution). Sub-project 3 is approved and split into independently
  green scene-core/migration and macOS-shell deliveries; only its first slice
  is implemented locally at this point. Foundation spec:
  docs/superpowers/specs/2026-08-26-gama-umbrella-foundation-design.md
- Scene-first integration (2026-08-27): the scene API, atomic in-repository
  migration, lifecycle channel, non-generic host, typed window commands, and
  primary-only non-window backends reached `main` through consolidation PR
  #19 (merge 7599a56). Honest process residual: PR #19 merged while four of
  six acceptance jobs were still running, so the selected green-before-merge
  policy was not followed; its merge-SHA push matrix remains the authoritative
  hosted proof and must be recorded only after all six jobs finish green.
  The residual scene-evidence/ADR diff remains isolated in PR #18 and must not
  be mistaken for a second implementation.
- macOS application shell (2026-08-27): `GamaAppleShell` and
  `gama-apple-demo` are implemented on `feat/apple-multiwindow-shell` from the
  consolidated main. Six offscreen AppKit tests locally prove launch
  selection, singleton/group identity, independent hosts/draw lists, command
  validation/draining, addressed delegate lifecycle, non-vetoable close,
  last-window residency, Dock reopen, and once-only termination. Local full
  gates, hosted PR proof, post-merge proof, and the supplemental manual Dock/
  Command-Q smoke remain separate acceptance layers; do not mark the shell
  shipped until the required automated layers are green.
- Linux sanitizer policy repair (2026-08-27): the XCTest-hosted ASan process
  keeps `detect_leaks=0` after PR #24 proved the generated harness retains 7
  allocations / 432 bytes with zero Gama frames. Leak coverage now runs in the
  separate `gama-leak-check` executable, which constructs and destroys a real
  `FrameHost` without any test harness under `detect_leaks=1`. Its required
  `--deliberate-leak` control retains a GamaCore `Signal`, and the gate passes
  only when the clean process exits zero while the control produces LSan's
  exact configured failure code and diagnostic. The broad `leak:XCTest`
  suppression is deleted. Darwin cannot supply this proof; hosted Linux is the
  acceptance authority.
- Acceptance-run continuity risk (2026-08-27): main has had no COMPLETED
  acceptance run since 33044975550 (pre-#19). Post-#22 run 33048024225 was
  cancelled by the #24 push and post-#24 by the #26 push — ci.yml's
  concurrency group is `cancel-in-progress: true`, so those closely spaced
  merges cancelled the previous merge's proof. This is missing evidence,
  not a structural blocker: a quiet merge interval or the existing
  `workflow_dispatch` entry point can produce a completed main run. Two
  optional continuity improvements remain Donald's call: mark the six jobs
  required (blocks merges until green, also fixes the merged-while-red
  pattern), and/or exempt `refs/heads/main` from cancel-in-progress so
  post-merge proofs are less likely to be superseded.
- Consolidation complete + specs finalized (2026-08-27, Donald's "merge all
  into main / finish all" session): PRs #20 (doc-coverage count), #21
  (macOS shell + gama-apple-demo), and #22 (ledger) merged; local main ==
  origin/main (afbb5c1); the two /private/tmp shell/consolidate worktrees
  are gone and no branch content remains outside main. Honest residual:
  PR #21 merged with four of six acceptance jobs still pending (Embedded +
  WASM green at merge); the post-#21 main run was superseded/cancelled, so
  main's hosted proof rides on the post-#22 acceptance run 33048024225 —
  record its conclusion here. A local union gate (main + both branches:
  119 tests / 32 suites green, apple + boundaries + docs) provides the
  local layer.
- Sub-projects 2 and 4 APPROVED (2026-08-27): Donald resolved all open
  questions via decision prompt — first-party GamaPlatformServices in
  plugin V1 (.filesystem real); full contribution surface (slots + scenes +
  commands) in plugin V1; com.donaldfilimon.gama.* confirmed with a
  Developer ID cert in hand (release-macos.sh is real V1 scope);
  wasm-site and .app packaging slices proceed in parallel on the
  scene-first shell's gama-apple-demo payload; Distribution/ manifest
  lands now. Approved specs:
  docs/superpowers/specs/2026-08-27-plugin-runtime-design.md and
  docs/superpowers/specs/2026-08-27-packaging-design.md (drafts annotated
  SUPERSEDED, kept for rationale). Implementation proceeds in gated
  slices; green-before-merge is the rule each slice must actually honor.
- Slice C approved in full (2026-08-27, Donald): frame-pump unification with
  a single resize policy (ADR 0007 leaves Provisional), the validated
  non-Sendable Signal redesign (ADR 0003 interim to be superseded), and all
  remaining Slice C items as gated slices. It remains blocked on actual
  wave-1 integration: packaging PR #32 is merged, but DocC-catalog PR #28
  must merge and the plugin-runtime post-merge hardening must be green
  before Slice C begins. Branch existence and local gates do not satisfy
  this boundary.
- Wave-2 structural designs authored (2026-08-27): frame-pump unification
  (HostPump, eager resize policy, per-backend migration slices; supersedes
  ADR 0007 when implemented) and the Signal redesign (non-Sendable with
  unavailable conformance, sending transfer, App drops Sendable; supersedes
  ADR 0004 when implemented). Specs:
  docs/superpowers/specs/2026-08-27-frame-pump-unification-design.md,
  docs/superpowers/specs/2026-08-27-signal-redesign-design.md.
  Implementation waits for the wave-1 branches (plugin runtime, packaging,
  DocC catalogs) to land.
- Plugin runtime + capability model V1 (2026-08-27): sub-project 2
  implemented on feat/plugin-runtime-v1 per the approved spec
  (docs/superpowers/specs/2026-08-27-plugin-runtime-design.md). Delivered:
  stdlib-only GamaPlugin (manifest/grants/typed errors/unforgeable
  handles/executor-confined PluginRuntime/PluginSlot), the full
  contribution surface (namespaced scene contributions with typed
  primary-role rejection, PluginScenes scene integration consumed by the
  existing scene graph and AppKit shell, deterministic host-bound
  commands), GamaPlatformServices (HostServices.standard: stderr log,
  monotonic clock, real scoped FilesystemProvider with lexical
  containment, no symlink resolution), a demo status-line slot in
  gama-demo, extended check-boundaries.sh greps (GamaPlugin held to the
  GamaCore rules; inverse grep fencing GamaPlatformServices out of
  portable targets), docs/Plugins.md with the Tier-1 enforcement-honesty
  stance, and 34 Swift Testing cases. Evidence at delivery time: local
  check-apple.sh, check-boundaries.sh, check-docs.sh,
  check-doc-coverage.sh green plus a full swift test run (record exact
  results in the PR). Deferred, recorded in tasks/todo.md: Tier 2/3,
  .network, scope subsumption, discovery, persistence, and shell
  teardown of contributed windows on uninstall. Hosted proof is the
  six-job matrix on the PR; merge only when green.
- Packaging & distribution V1 (2026-08-27): sub-project 4 approved
  (docs/superpowers/specs/2026-08-27-packaging-design.md) and implemented on
  feat/packaging-v1. Locally proven with real exit codes: bundle-web.sh
  (pinned-SDK wasm build, site assembled to /private/tmp/gama-dist/web,
  headless-Chrome smoke against the assembled directory), gama-apple-demo
  --smoke (offscreen NSApplication, 36 draw commands, exit 0), and
  bundle-macos.sh ("Gama Demo.app" staged outside the iCloud tree from the
  gama-apple-demo manifest, plutil lint, ad-hoc deep-strict codesign verify,
  smoke launch). release-macos.sh (Developer ID + notarytool + stapler) is
  implemented with hard credential gating; the gate's fail-closed refusal is
  locally proven and the credentialed path is deliberately unclaimed until a
  run with GAMA_CODESIGN_IDENTITY/GAMA_NOTARY_PROFILE passes. CI now stages
  and uploads both artifacts (macos-app, wasm-site); hosted proof rides on
  the packaging PR's six-job matrix and must be recorded only when green.
  Manifests in Distribution/ carry identity only, parsed by the fail-closed
  scripts/lib/manifest.sh reader.
- Packaging review hardening (2026-08-27, PR #32): repaired all seven active
  review findings without weakening a gate. The flat-TOML grammar now validates
  whole identifiers; macOS staging canonicalizes containment and uses
  plist-aware branding; the wasm bundler verifies the exact Swift revision and
  the manifest-configured page title; CI uploads a mode-preserving `ditto` ZIP;
  and the credentialed release path rebuilds its downloadable ZIP after
  stapling. Local regression probes, `check-toolchain-pins.sh`, the real macOS
  app bundle gate, transport extraction/signature verification, and the real
  wasm browser bundle gate are green. Exact repair head 77e3160 passed all six
  acceptance jobs plus Devin Review and merged through PR #32 as 3b4c83a;
  do not infer that result from an earlier head.
- Plugin runtime post-merge hardening (2026-08-27): PR #33 merged only
  after its original head passed all six acceptance jobs, but a later
  review identified five substantive defects. The follow-up gives each
  plugin a stable slot identity retained across peer removal, isolates and
  cancels plugin-owned observations on failed activation/uninstall,
  invalidates the host after successful install/uninstall, revokes cached
  commands at uninstall, and rejects internal empty filesystem components
  while retaining one trailing separator. Focused evidence is 39 Swift
  Testing cases in six suites on the pinned toolchain; the follow-up's own
  exact-head hosted matrix is still required and must not be conflated with
  PR #33's already-green head.
- Slice C wave 2, structural half (2026-08-27, /goal continue): the two
  headline items of the audit's top structural row landed on branch
  slice-c/wave-2-frame-pump-and-signal — frame-pump unification (ADR 0008
  supersedes 0007) and the non-Sendable Signal redesign (ADR 0009
  supersedes 0004). Both approved specs needed correction against reality
  and both corrections are recorded rather than absorbed: the pump spec's
  D2 signature could not compile (CellBuffer lives in GamaDraw, which
  depends on GamaCore), and the Signal spec's claim that an unavailable
  conformance "prevents" retroactive re-conformance is false — measured on
  the pinned snapshot it is a warning (#UnavailableSendableConformance),
  so what it actually buys is a named, attributable diagnostic. Proposed,
  NOT Current: local gates are green (167 tests, boundaries incl. two new
  confinement negative fixtures, c-abi, wasm, docs, doc-coverage) but no
  PR is open and no hosted six-job matrix has run on this work.
- Ledger truth-up (2026-08-27): sub-projects 2, 3, and 4 were closed after
  verifying their own stated conditions were already met — PR #37 head
  b11297d, PR #21 head ca95b220, and PR #32 head 77e3160 each passed all
  six hosted jobs. The ledger, not the work, was stale. Sub-project 3
  carries a named residual: its literal post-merge run was cancelled by
  the concurrency group, so proof rides on green descendant main runs.
- Full local acceptance matrix (2026-08-27): `./scripts/check.sh` was run
  end to end on this machine for the first time, exit 0, 17 OK lines,
  including the three gates the docs describe as CI-or-hardware-only. Two
  environment facts made that possible and correct two stale notes in
  ~/CLAUDE.md: check-linux.sh needs no Linux (it cross-compiles with the
  installed static-linux SDK, ~1s), and `timeout` IS installed
  (/opt/homebrew/bin, coreutils) which check-android-emulator.sh depends
  on. The emulator gate additionally needs ANDROID_HOME, adb on PATH, and
  an already-booted device — it does not boot one itself.
- Ledger truth-up round 2 (2026-08-28): re-verified every open checkbox in
  tasks/todo.md against the tree rather than against the list, because this
  repo has already been bitten once by "the ledger, not the work, was stale".
  Five entries were stale and are now closed with the evidence that closes
  them: the libm/portable-symbol hole (scripts/check-portable-symbols.sh,
  wired into check-boundaries/check-linux/check-wasm with a compiled negative
  fixture that must fail and must name `_roundSlowPath`), the Renderer double
  covering AppRuntime.run(), SIGTERM/SIGHUP/atexit/SIGWINCH terminal restore,
  macro Fix-Its, and the scale-aware ProgressView. Two entries stay open and
  honest: the Android-emulator KVM finding is unrefuted but is peer territory
  (PR #52 is open against that exact job), and VoiceOver is genuinely
  unimplemented — the only accessibility hit in Sources is the doc comment at
  GamaHostView.swift:53 promising the adapter.
  [SUPERSEDED 2026-08-29 — both clauses in the preceding sentence are now
  FALSE, and are kept rather than edited because how they went stale is the
  point. KVM closed via PR #52 (b0de7d9). VoiceOver closed via PR #54
  (591134d): Sources/GamaDraw/AccessibilitySnapshot.swift and
  Sources/GamaAppleUI/GamaHostAccessibility.swift both exist on main. The
  VoiceOver clause was CORRECT when written that morning and falsified hours
  later by a concurrent merge — the same failure mode a truth-up PR is most
  exposed to, which is why this ledger now runs an evidence audit against the
  exact tip before it is written.] Local baseline at truth-up
  time: ./scripts/check-apple.sh exit 0, 205 tests in 44 suites.
- Remaining umbrella scope after the truth-up, in roadmap order: Task 4.2
  items 4 (VoiceOver), 6 (presentDiff/forEachRun, measure first), 7
  (~Copyable CellBuffer/Terminal), 8 (StrictMemorySafety +
  InternalImportsByDefault), 9 (MLIR emitter unification); Task 5 (Apple host
  file split + trace-backed profiling); Task 6 (GamaSwiftUI / Liquid Glass,
  spec first — the roadmap's named design spec does not exist yet); Task 7
  (closeout). Windows-on-6.5-dev remains an external blocker, not a claim.
- CI health restored (2026-08-28): main's acceptance matrix was RED on the
  Android job and had been intermittently so for a long time. Two distinct
  causes, both closed by PR #52 (merged b0de7d9) on a green exact-head matrix
  at 46a8037.
  (1) The emulator has never had KVM. The hosted runner's kvm group is empty,
  so android-emulator-runner fell back to TCG software emulation on every run
  this job has ever made — boots of 380,965 ms passing and 720,220 ms failing
  against a 720 s allowance, i.e. a coin flip, which the repo had been
  mislabelling as "adb install flakes are infra, not product". The udev rule
  from the action's own README, added as a STEP in the existing job so the six
  name-pinned ruleset contexts stay intact, fixed it: the log now shows
  `crw-rw-rw- ... /dev/kvm` and `disable Linux hardware acceleration: false`,
  and the job runs in 5m20s instead of ~21 min.
  (2) The merge at 52e8277 silently deleted two readiness variable definitions
  while keeping their references, killing the gate in 56 ms with no output at
  all. Restored, and guarded by a reference-versus-definition assertion that is
  mutation-verified against the broken script.
  Evidence: main's post-merge acceptance run 33193668881 at b0de7d9 completed
  GREEN on all six jobs. That is also the first COMPLETED green main run in a
  while, which closes the "acceptance-run continuity risk" entry above — its
  proposed fix landed independently (main-push events now get run_id-unique
  concurrency groups, so a later merge can no longer cancel an earlier merge's
  proof), and ruleset 21626078 now has bypass_actors: [] with
  current_user_can_bypass: never, making the repeatedly-recorded
  "merged while red" residual structurally impossible rather than a matter of
  discipline.
  Umbrella goal stays in_progress: Roadmap items 7 and 8 are untouched
  multi-session work, and item 9 has an approved design spec (PR #55) but no
  implementation.
