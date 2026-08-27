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

## Documentation depth (surveyed 2026-08-26, not yet started)
- [ ] DocC doc-comment coverage: ~16% of ~486 public decls have /// docs
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
- [ ] DocC catalogs exist only for GamaCore (7 articles); GamaDraw and the
      backends have none. Adding catalogs requires extending check-docs.sh,
      which hardcodes the GamaCore symbol-graph/catalog paths.
- [ ] check-docs.sh's Capabilities.md grep is tautological (matches the
      table header "Current evidence"); tighten if a stronger claim-honesty
      check is wanted.

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
- [ ] Hosted matrix green on the refresh PR before merge
- [ ] Linux ASan: re-enable `detect_leaks=1` once a hosted run proves the
      Swift Testing runner is leak-clean (CI still sets detect_leaks=0)
- [ ] MemberImportVisibility spike on strictCore (direct-import fallout in
      tests); keep off until Apple + Embedded stay green

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
- [ ] Slice C (needs Donald's sign-off / design decisions — Proposed only):
      unify the four divergent frame pumps + pick one resize policy (audit's
      top structural item; changes observable resize semantics); Signal
      @unchecked Sendable redesign (Synchronization is banned in GamaCore —
      options are per-field nonisolated(unsafe), non-Sendable + drop
      App: Sendable, or documented confinement — confinement comments landed
      2026-08-27; redesign still Proposed); MacroSpec FixIts for untested
      diagnostic roles; VoiceOver
      accessibility from currentDrawList; SIGTERM/SIGHUP/atexit terminal
      restore + SIGWINCH; presentDiff/forEachRun allocation work (measure
      first); ~Copyable on CellBuffer/Terminal (two-part deinit rework);
      scripted in-memory Renderer double to cover AppRuntime.run();
      StrictMemorySafety + InternalImportsByDefault upcoming features
      (verified live on this snapshot; import-regex tightening is the
      prerequisite); MLIR emitter unification; scale-aware ProgressView.

## Later sub-projects (each needs its own spec first)
- [ ] Sub-project 2: plugin runtime + capability model — DRAFT written
      (docs/superpowers/specs/drafts/2026-08-26-plugin-runtime-draft.md),
      awaiting Donald's review of its 3 open questions
- [ ] Sub-project 3: app shell, windowing, lifecycle — DRAFT written
      (docs/superpowers/specs/drafts/2026-08-26-app-shell-draft.md),
      awaiting review; packaging's .app slice depends on this
- [ ] Sub-project 4: packaging & distribution — DRAFT written
      (docs/superpowers/specs/drafts/2026-08-26-packaging-draft.md),
      awaiting review; wasm site slice is independent of 2/3
