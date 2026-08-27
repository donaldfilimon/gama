# Todo

## Umbrella foundation (sub-project 1)
- [x] Adopt donaldfilimon/gama history into ~/Desktop/Gama (56 commits, all branches)
- [x] Pin main-snapshot-2026-08-21; re-pin scripts + embedded gate; local gates green
- [x] Remove Qt adapter + gate + CI step + doc references
- [x] Push feat/swift-65-dev-umbrella; open PR #7; CI matrix running
- [x] PR #7 matrix green → merged to main (74e77df)
- [x] Retire ~/dev/active/gama-swift to ~/dev/archive; update ~/CLAUDE.md rows

## Umbrella foundation follow-ups
- [x] Update Toolchains.toml to the 6.5-dev reality. Done 2026-08-26 (code
      review of f509e2c..11ef0a9): restructured into [snapshot] (+ .macos /
      .linux_x86_64), [xcode_default] (6.4, xcodebuild platform gates only),
      [windows_exception] (6.4.x), and the three 6.5-dev SDK bundles. All
      URLs/SHA-256 taken from .github/workflows/ci.yml; swift_revision
      95c5142e84b82c1, llvm_revision 64c3046d94ae7cc and swiftc_sha256
      dbbd4d7b… measured locally. swiftlang/clang under [xcode_default] left
      untouched (unverified); [swift_syntax] keeps its revision pin and drops
      the misleading 6.4.x tag.

## Documentation depth (surveyed 2026-08-26)
- [x] DocC doc-comment coverage: ~16% of ~486 public decls have /// docs
      (GamaCore 60/364, GamaTUI 2/34, GamaAppleUI 2/26). Pattern: type- and
      algorithm-level docs exist; member-level (properties, inits, methods)
      are mostly bare. Author them module by module, starting with GamaCore.
      CLAIMED 2026-08-26 21:53 by the goal-loop session; working in worktree
      /private/tmp/gama-docc-wt on branch docs/docc-member-coverage to keep
      the shared checkout clean. Slice 1 DONE 22:00: Primitives (139→0
      undocumented), View (58→0), Geometry (50→0); comments-only (389+/0-),
      check-docs.sh green; PR #10 open, merge only when its matrix is green.
      Slices 2+3 DONE 22:11 (0bddca1 Style/State/RenderNode 148+, aae753a
      Runtime/FrameHost/Layout/TextLayout 95+): GamaCore now has ZERO
      undocumented public declarations across all ten files (single-line
      multi-case enum rows deliberately left unsplit); every slice verified
      comments-only and check-docs.sh green; pushed to PR #10.
      Slice 4 DONE 22:19 (1f9f3b3, 150+): GamaTUI and GamaAppleUI at zero
      undocumented public decls; gated by check-docs.sh AND a full pinned
      swift build (compiles both targets); Windows docs stay claim-honest.
      All four slices pushed to PR #10 — remaining action: merge PR #10 when
      its matrix is green, then mark this item done.
      CLOSED 2026-08-27: PR #10 merged (c718888) — honest residual: merged
      while the matrix was red (see the P0 repair item below; repaired by
      PR #14 on a green six-job matrix). Superseded by the stronger
      outcome: zero undocumented public declarations package-wide, enforced
      by the check-doc-coverage.sh gate in check.sh and CI.
- [x] DocC catalogs for GamaDraw and GamaTUI added and check-docs.sh
      generalized to build every module catalog (was: GamaCore-only with
      hardcoded paths; closed 2026-08-27 by the scene-first consolidation,
      merged via PR #19).
- [x] check-docs.sh's Capabilities.md grep is tautological (matches the
      table header "Current evidence"); tighten if a stronger claim-honesty
      check is wanted. CLOSED 2026-08-27 by the docs overhaul: the grep now
      requires the Status vocabulary legend heading.

## Swift 6.5-dev refresh (2026-08-27)
- [x] Pin-consistency gate: `scripts/check-toolchain-pins.sh` fails if CI,
      check-script defaults, or `.swift-version` drift from Toolchains.toml
- [x] Everyday invocation: `swiftly run` documented in AGENTS.md / CLAUDE.md /
      README.md / docs/Toolchain.md
- [x] XCTest → Swift Testing globally (gamaTests, AppleHost, POSIX, macros)
- [x] Macro tests: SwiftSyntaxMacrosGenericTestSupport, no XCTest product
- [x] `RenderNode.group` flatten sentinel; ZStack(.topLeading) stays overlay
- [x] Docs: docs/Testing.md, docs/Toolchain.md, Capabilities remaining column,
      GamaCore.docc/Testing.md
- [x] Hosted matrix green on the refresh PR before merge — VIOLATED in the
      event (PRs #10/#13 merged while red; honest residual recorded in
      goals.md), repaired forward by PR #14 on a fully green six-job
      matrix. Main's current proof rides on the post-#16 acceptance run
      (33044975550, watched 2026-08-27).
- [ ] Linux ASan: re-enable `detect_leaks=1` once a hosted run proves the
      Swift Testing runner is leak-clean (CI still sets detect_leaks=0 at
      ci.yml:83)
- [x] MemberImportVisibility spike on strictCore (direct-import fallout in
      tests); keep off until Apple + Embedded stay green. CLOSED
      2026-08-27: enabled in strictCore (Package.swift:13, hygiene-flags
      commit e038ad6); hosted Apple + Embedded proof rides on the
      post-#16 matrix run.

## Code follow-ups from Codex review of PR #10 (docs narrowed in f0078dc;
## behavior itself unchanged — each needs a code PR with tests)
- [x] P1: ZStack(.topLeading) flatten sentinel — fixed via `RenderNode.group`
      (View.swift flattenChildren / TupleView / ForEach). Regression in
      BuilderTests.zStackTopLeadingLayersInsteadOfFlattening.
- [x] Border title: paint uses `>= displayWidth+4` and places `" title "`
      at minX+1 so a natural-size title is visible (BorderTitleTests).
- [x] Divider orientation follows the containing stack axis; a 1×1 HStack
      Divider paints `│` (DividerAxisTests).
- [x] TextField consumes C0/DEL `.character` events (including embed) and
      does not insert them (TextFieldControlTests).
- [x] TextLayout treats U+231A (and a documented Misc Technical subset) as
      wide; other symbols stay narrow unless VS16 is present
      (TextLayoutEmojiTests).
- [x] Button focus wrap wins over a custom-colored label (outer-wins
      style merge in CellPainter; ButtonFocusStyleTests).

## Modern-Swift sweep (audited 2026-08-27, three parallel audits; execute in
## gated slices — slice A avoids PR #10's files until that PR merges)
- [x] Slice A (non-GamaCore/TUI/AppleUI): Package.swift — strictCore on
      GamaMacrosImpl and GamaWebDemo; GamaWASM on GamaTests; Extern only on
      GamaWASM. check-boundaries.sh import regex tightened. HTMLSerializer
      off wasm32 and tested. CellBuffer Hashable/Sendable; DrawList.decode
      typed throws; encode reserveCapacity; UTF-8 validated in-place;
      leading-trim uses space width 1. Embed raw-buffer reuse, resize
      clamp, FRAME_TOO_LARGE, nonisolated @_cdecl (incl. Android), opaque
      context + abi_version. MLIR internals internal; i64 is Int64 for
      NodeIDs. Gama @_exported; hello() retired.
- [x] Slice B: FrameHost ~Copyable + HostActionStore; dirty is let;
      invalidate() non-mutating; InteractiveRegion; BorderGlyphs;
      RenderNode/LaidOutNode Hashable; exhaustive flexPriority/flexMinimum;
      .resize payload stored as lastSize. TUIRenderer.end defer-clears
      session; Musl/Android write imports; hoisted readBuffer; 1-byte ESC
      compare; WinSDK BOOL `_ =`. AppleUI let colors, @MainActor closures,
      reinstall tears down previous session, italic via NSFontDescriptor.
- [ ] Slice C — APPROVED IN FULL 2026-08-27 (Donald, decision prompt):
      unify frame pumps now (finish ADR 0007); adopt the validated
      non-Sendable Signal design (supersedes ADR 0003's interim); execute
      every remaining item in gated slices, measure-first where noted.
      BLOCKED ON INTEGRATION: do not begin wave 2 until DocC-catalog PR
      #28 is actually merged and the plugin-runtime post-merge hardening
      follow-up is green. Packaging PR #32 and plugin PR #33 are merged;
      an open branch or a locally green gate is not integration.
      Original scope list:
      unify the four divergent frame pumps + pick one resize policy (audit's
      top structural item; changes observable resize semantics); Signal
      @unchecked Sendable redesign (Synchronization is banned in GamaCore —
      options are per-field nonisolated(unsafe), non-Sendable + drop
      App: Sendable, or documented confinement — confinement comments landed
      2026-08-27; redesign still Proposed. Candidate design validated by a
      fresh-agent baseline 2026-08-27: non-Sendable Signal with the
      conformance marked `@available(*, unavailable)` so it cannot be
      retroactively "fixed", region-based isolation + `sending` transfer
      into the host — zero runtime cost, honest on bare metal); MacroSpec FixIts for untested
      diagnostic roles; VoiceOver
      accessibility from currentDrawList; SIGTERM/SIGHUP/atexit terminal
      restore + SIGWINCH; presentDiff/forEachRun allocation work (measure
      first); ~Copyable on CellBuffer/Terminal (two-part deinit rework);
      scripted in-memory Renderer double to cover AppRuntime.run();
      StrictMemorySafety + InternalImportsByDefault upcoming features
      (verified live on this snapshot; import-regex tightening is the
      prerequisite); MLIR emitter unification; scale-aware ProgressView.

## Docs overhaul (planned + largely executed 2026-08-27; see docs/README.md)
- [x] P0 repair: PR #10 merge-forward reverted sweep hunks on main
      (RenderNode.group + Hashable, ~Copyable hosts, non-mutating
      invalidate, hello() docs) leaving main non-compiling with a red
      matrix; #10/#13 were merged while red (honest residual). Fixed
      forward on fix/restore-sweep-semantics (PR #14) + cherry-picked the
      sweep contract tests; merge only on green matrix.
- [x] Claim honesty: gama.group now gate-proven by an MLIR suite test;
      Capabilities.md gained the Status vocabulary legend; check-docs.sh's
      tautological grep now requires the legend heading (closes the
      long-standing item above); Testing.md file map completed; goals.md
      74-test line superseded-marked (peer session).
- [x] GamaCore.docc sweep alignment: Topics curate the sweep-era types;
      BackendAuthoring documents noncopyable hosts; Architecture/
      CompositionAndState document group vs overlay; Migration gained the
      6.5-dev adoption section.
- [x] Member docs: zero undocumented public declarations package-wide
      (42 remaining decls documented across GamaDraw/GamaEmbed/GamaMLIR/
      GamaWASM/GamaMacrosImpl; heuristic scan + zero-warning DocC + full
      pinned build).
- [x] Guides: docs/README.md index, CONTRIBUTING.md gate reference,
      docs/backends/{TUI,AppleUI,WASM,CEmbed,Android}.md,
      docs/MLIRDialect.md; README products table completed (13 products)
      with Examples/WebHost pointers. Per-target .docc catalogs stay
      deliberately deferred (item above).
- [x] ADRs: docs/adr/0000-0007 (own-the-rendering, toolchain pinning,
      Swift Testing only, Signal confinement interim, DrawList v1,
      noncopyable hosts, frame pumps Provisional).
- [x] check-doc-coverage.sh: deterministic per-module symbol-graph
      coverage gate (docComment presence; origin- and declared-in-module-
      filtered so re-exports and protocol-synthesized members are not this
      module's debt; path-keyed allowlist requiring justifications, empty
      at adoption); wired into check.sh after check-docs and the macOS
      boundaries-and-documentation CI step; verified deterministic (two
      identical green runs). Adoption also split the single-line
      multi-case enum rows (Key, alignments) with per-case docs, fixed 7
      GamaEmbed doc comments that sat between @_cdecl and their function
      (compiler-accepted, symbol-graph-invisible), and converted
      GamaEmbed.h to per-symbol /** */ docs.

## Later sub-projects (each needs its own spec first)
- [ ] Sub-project 2: plugin runtime + capability model — APPROVED
      (docs/superpowers/specs/2026-08-27-plugin-runtime-design.md; the
      2026-08-26 draft holds rationale). V1 IMPLEMENTED 2026-08-27 on
      feat/plugin-runtime-v1: GamaPlugin (stdlib-only capability core,
      PluginRuntime, PluginSlot), scene + command contribution surface
      (PluginScenes consumed by the scene graph and the AppKit shell,
      offscreen shell test included), GamaPlatformServices
      (HostServices.standard + scoped filesystem with hostile-path
      tests), demo status-line slot, extended check-boundaries.sh, and
      docs/Plugins.md. PR #33 merged after its exact-head six-job matrix
      passed. Post-merge review found five substantive defects: unstable
      survivor slot identity, host-wide plugin observation ownership,
      missing lifecycle invalidation, callable cached commands after
      uninstall, and internal empty filesystem components. The hardening
      follow-up fixes those contracts and has 39 focused Swift Testing
      cases green locally; keep this item open until that follow-up's own
      exact-head six-job matrix is green. Deferred inside sub-project 2:
      Tier 2 (dylib loading), Tier 3 (out-of-process ABI), `.network`, scope
      subsumption/path normalization, manifest macros,
      discovery/scanning, plugin persistence, and shell teardown of
      contributed windows on uninstall (uninstall stops future graph
      compiles from contributing; a live window stays open until closed
      through window actions — next slice if wanted).
- [ ] Sub-project 3: scene-first app shell, windowing, lifecycle — APPROVED;
      scene core integrated on main and the macOS shell is implemented/local-
      proven on its delivery branch. Keep open until the shell PR and its
      post-merge six-job matrix are green.
      design at docs/superpowers/specs/2026-08-27-scene-first-app-shell-design.md.
      Scene core/migration and macOS shell are separate green delivery slices;
      packaging's .app slice depends on both.
- [ ] Sub-project 4: packaging & distribution — APPROVED
      (docs/superpowers/specs/2026-08-27-packaging-design.md; the 2026-08-26
      draft is kept for inventory and rejected alternatives). V1 implemented
      2026-08-27 on feat/packaging-v1:
      - Landed and locally proven: scripts/lib/manifest.sh (fail-closed
        flat-TOML reader), Distribution/ manifests + Info.plist.in
        (com.donaldfilimon.gama.*, 0.1.0), scripts/bundle-web.sh (site
        assembled to $GAMA_DIST_ROOT/web, browser smoke green against the
        assembled directory), gama-apple-demo --smoke (offscreen
        NSApplication launch gate, non-empty DrawList), and
        scripts/bundle-macos.sh (staged .app outside the iCloud tree,
        plutil lint, ad-hoc deep-strict codesign, smoke launch, all green).
      - CI-gated (hosted proof pending the PR matrix): the macOS job's
        bundle step + mode-preserving macos-app ZIP upload and the wasm job's
        bundle step + wasm-site upload. PR review hardening validates whole
        manifest identifiers, canonicalizes the dist root, uses plist-aware
        branding, applies and browser-verifies `[web].title`, and checks the
        exact Swift revision.
      - Credential-gated: scripts/release-macos.sh Developer ID +
        notarization path is implemented, rebuilds the download ZIP after
        stapling, and its fail-closed gating is locally proven; no credentialed
        run has occurred, so the notarized artifact is not claimed.
      - Deferred per spec: embed SDK dir, Linux static binary, Windows
        staged dir, Android assembleRelease + keystore, gama CLI veneer,
        iOS-family .ipa. No icon source exists, so the iconutil path is
        implemented but unproven. Keep open until the packaging PR and its
        six-job matrix are green.
