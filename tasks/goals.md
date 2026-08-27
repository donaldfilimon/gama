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
  0 failures; `check-docs.sh` zero-warning gate green. CLAUDE.md expanded into
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
- Sub-projects 2-4 Proposed: drafts written and committed under
  docs/superpowers/specs/drafts/ (plugin runtime + capability model; app
  shell/windowing/lifecycle; packaging & distribution). Each is DRAFT ONLY —
  no code, no approval — and ends with open questions Donald must decide
  before its spec is finalized. Foundation spec:
  docs/superpowers/specs/2026-08-26-gama-umbrella-foundation-design.md
