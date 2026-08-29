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
      EXTENDED 2026-08-27 (branch docs/docc-catalogs-backends): curated
      catalogs added for GamaAppleUI, GamaAppleShell, GamaWASM, and
      GamaMLIR; check-docs.sh needed no further changes (its discovery
      loop already builds every Sources/*/*.docc catalog) and now gates
      seven zero-warning archives. Honest residuals: GamaEmbed is
      deliberately skipped because its CInterface.swift doc comment links
      ``GamaCore/App``, which cannot resolve in the per-module docc pass,
      so a GamaEmbed catalog requires a one-line source doc-comment fix
      first (out of scope for the docs-only branch); GamaWASM's catalog
      is prose-only because its entire public API is arch(wasm32)-gated
      and absent from the host symbol graph.
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
- [x] Linux leak detection: replaced the rejected `leak:XCTest` suppression
      with a harness-free executable and required negative control. The
      original premise was wrong: the runner is not leak-clean and moving
      every suite to Swift Testing did not make it so.
      Evidence — PR #24's Linux job (run 33048676959) under detect_leaks=1
      reports exactly 7 indirect leaks / 432 bytes, every stack rooted in
      `libXCTest.so` (`XCTestSuiteRun.init`, `XCTMain`, `XCTMainMisc`) or
      reached only through those frames (Foundation
      `URL.lastPathComponent` called by XCTMain). ZERO Gama frames.
      SwiftPM's generated test entry point still runs the XCTest harness
      even with no XCTest suites, and that harness allocates
      process-lifetime suite metadata it never frees before exit. So a
      "hosted trial green under detect_leaks=1" is unreachable while the
      generated runner keeps its XCTest half — waiting for one is waiting
      forever.
      Resolution: `swift test --sanitize address` keeps `detect_leaks=0` for
      address-safety coverage, while `scripts/check-linux-leaks.sh` builds and
      directly executes `gama-leak-check` under `detect_leaks=1`. Its clean
      path exercises `FrameHost`; `--deliberate-leak` retains a real GamaCore
      `Signal`. The script requires clean exit 0, control exit 86, the control
      marker, and LSan's diagnostic, with no suppression file. This makes a
      disabled detector fail the contract instead of producing false green.
- [x] MemberImportVisibility spike on strictCore (direct-import fallout in
      tests); keep off until Apple + Embedded stay green. CLOSED
      2026-08-27: enabled in strictCore (Package.swift:13, hygiene-flags
      commit e038ad6); hosted Apple + Embedded proof rides on the
      post-#16 matrix run.

      DECISION 2026-08-27 (Donald, decision prompt): build a harness-free
      leak test rather than closing this at detect_leaks=0 or retrying the
      rejected suppression file (PR #31, closed). A leak target that runs
      WITHOUT the Swift Testing harness lets detect_leaks=1 return with a
      real negative control, since the measured leak was the harness
      process, not Gama.
      CONSTRAINT (measured): LeakSanitizer is Linux-only — detect_leaks is
      unsupported on Darwin — so this gate cannot be locally proven on this
      Mac at all. Its evidence is necessarily hosted-only, which makes the
      Linux CI job the sole proof and means the negative control matters
      more than usual: without it, "no leaks found" is indistinguishable
      from "detector disabled".

## Code follow-ups from Codex review of PR #10 (docs narrowed in f0078dc;
## behavior itself unchanged — each needs a code PR with tests)
- [x] P1: ZStack(.topLeading) flatten sentinel — fixed via `RenderNode.group`
      (View.swift flattenChildren / TupleView / ForEach). Regression in
      BuilderTests.zStackTopLeadingLayersInsteadOfFlattening.
- [x] Border title: measurement and paint share the non-empty
      `displayWidth+4` minimum; natural ASCII/Unicode captions fill their
      reserved top edge, while an empty caption adds no padding
      (BorderTitleTests).
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

      INTEGRATION BLOCKER CLEARED 2026-08-27: DocC-catalog PR #28 merged
      (18ea46e) and the plugin-runtime hardening follow-up PR #37 is green
      at its exact head (b11297d). Wave 2 is unblocked.

      WAVE 2 STRUCTURAL HALF LANDED 2026-08-27 on branch
      slice-c/wave-2-frame-pump-and-signal (not yet in a PR):
      - Frame-pump unification. One canonical HostPump owns resize policy,
        the dirty gate, and pump ordering; all four backends rewired (TUI,
        Embed, WASM, AppleUI). ADR 0008 supersedes 0007. Embed and WASM
        tests pass UNCHANGED, which is the spec's own proof that the
        canonical shape matches what they already did.
        SPEC AMENDED: D2 was unimplementable as written — it puts HostPump
        in GamaCore with an `emit: (borrowing CellBuffer)` closure, but
        CellBuffer is in GamaDraw, which depends on GamaCore. Split across
        the dependency edge (policy in GamaCore so it stays inside
        check-embedded.sh, which compiles GamaCore alone; buffer path as a
        GamaDraw extension). A fifth duplicated fragment the spec's table
        never named — per-backend buffer resizing — folded into
        CellBuffer.resizeIfNeeded, which normalizes before comparing.
      - Signal redesign. Signal is non-Sendable with an unavailable
        conformance; the laundering it enabled is removed from View, Scene,
        App, BuildContext, Binding, SubscriptionContext, State,
        GamaPluginProtocol, PluginContext, and plugin contributions.
        HostServices, the AppKit command channel, and ScenePayload keep
        @Sendable deliberately. ADR 0009 supersedes 0004.
        SPEC CORRECTED (measured, not inferred): the spec claimed the
        unavailable conformance "prevents the conformance from ever being
        retroactively fixed by a consumer". It does NOT. On the pinned
        snapshot `extension Signal: @retroactive @unchecked Sendable {}`
        still compiles, emitting warning #UnavailableSendableConformance
        plus a note at the declaration. What it buys is a named,
        attributable diagnostic a consumer must silence deliberately —
        more than a comment, not impossibility. Pinned by negative
        fixtures in Tests/Fixtures/Confinement/ driven from
        check-boundaries.sh (error.* must fail to compile; warn.* must
        compile AND emit the diagnostic). Folded into the existing
        boundaries gate rather than a new CI job, because the six required
        status-check contexts are name-pinned in repository ruleset
        21626078 and a new job would orphan them.
      Local evidence: check-apple 167 tests, boundaries (incl. 2
      confinement fixtures), c-abi, wasm, docs, doc-coverage all green.
      HOSTED PROOF OUTSTANDING — no PR opened yet, so nothing here is
      Current.

      LONG TAIL STILL OPEN (Donald chose "full wave 2, everything"
      2026-08-27): MacroSpec FixIts; VoiceOver from currentDrawList;
      SIGTERM/SIGHUP/atexit + SIGWINCH terminal restore; presentDiff/
      forEachRun allocation work (measure first); ~Copyable CellBuffer/
      Terminal; scripted Renderer double covering AppRuntime.run();
      StrictMemorySafety + InternalImportsByDefault; MLIR emitter
      unification; scale-aware ProgressView. Next slice is the Renderer
      double, because AppRuntime.run() was just rewired onto HostPump and
      the existing ScriptedRenderer (SceneTests.swift:305) covers only
      lifecycle — not frame production, the dirty gate, resize through
      run(), or renderer error propagation.

      LONG-TAIL STATUS RE-VERIFIED 2026-08-28 against the tree, not against
      this list. Four of the nine have landed and are now tracked as the
      numbered Roadmap Task 4.2 items below:
      - Renderer double: DONE. Tests/gamaTests/RuntimeLoopTests.swift, suite
        "Runtime loop" — begin/end ordering, the dirty gate, non-blocking
        follow-up polling, follow-up starvation vs quit, resize through
        run(), renderer-driven resize with no event, re-sync to begin's
        extent, renderer failure leaving the surface released, and ctrl-c.
      - Terminal restore: DONE. Sources/GamaTUISignal/GamaTUISignal.c
        installs SIGTERM/SIGHUP/SIGWINCH handlers and an atexit hook;
        Sources/GamaTUI/TerminalRescue.swift is the Swift face (SIGWINCH is
        edge-triggered once per delivery and has a test seam);
        Tests/gamaTests/TerminalRescueTests.swift covers it.
      - MacroSpec Fix-Its: DONE via PR #44 (already its own item below).
      - Scale-aware ProgressView: DONE.
        Tests/gamaTests/ProgressViewTests.swift pins the sub-cell boundary
        glyph, the 0.99-vs-1.0 distinction, an ulp-below-1 value that must
        not read as full, and NaN/±infinity/out-of-range clamping.
      STILL OPEN, and the actual remaining scope of this session: VoiceOver
      from currentDrawList; presentDiff/forEachRun (measure first);
      ~Copyable CellBuffer/Terminal; StrictMemorySafety +
      InternalImportsByDefault; MLIR emitter unification.

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

## Roadmap Task 4.2 (remaining Slice-C items, land in order)
- [x] Item 1: in-memory `Renderer` double covering `AppRuntime.run()`.
      Landed in Tests/gamaTests/RuntimeLoopTests.swift (suite "Runtime loop").
      Verified 2026-08-28: it covers begin/frame/event/end ordering and every
      exit path the roadmap named — the dirty gate, non-blocking follow-up
      polling, quit winning over continuous follow-ups, resize both through
      `run()` and driven by the renderer with no event, re-sync to the extent
      `begin` established, renderer-error propagation with the surface still
      released, and ctrl-c.
- [x] Item 2: terminal restoration for SIGTERM, SIGHUP, `atexit`, and
      SIGWINCH. Landed as the `GamaTUISignal` C shim
      (Sources/GamaTUISignal/GamaTUISignal.c: handlers for SIGTERM/SIGHUP/
      SIGWINCH plus a once-registered `atexit` restore) behind
      Sources/GamaTUI/TerminalRescue.swift, which exposes the full ordinary/
      `atexit` restoration path and an edge-triggered "true exactly once per
      delivered SIGWINCH" flag with a test seam. Covered by
      Tests/gamaTests/TerminalRescueTests.swift and
      Tests/gamaTests/POSIXTerminalIntegrationTests.swift; the C-side probe
      fixture is Tests/Fixtures/TerminalSignal/TerminalSignalProbe.c.
- [x] Item 3: macro diagnostic Fix-Its. PR #44 merged 2026-08-27 (8717a8c) with
      its exact-head six-job matrix green. Fix-Its added only where exactly one
      correct edit exists (reactive.var-only let->var, gated on the decl really
      being `let`; component.struct-only removes the attribute). The other three
      (reactive.needs-type, rgb.literal-required, rgb.malformed) deliberately
      have NO Fix-It and tests pin that absence. Mutation-verified: dropping the
      `let` gate fails "Reactive offers no let-to-var Fix-It on a property that
      is already var". A first attempt at that negative test used a `func` and
      never exercised the gate (mutation passed); replaced with a tuple-pattern
      binding that does.
- [x] Item 4: VoiceOver accessibility derived from `currentDrawList`. CLOSED
      2026-08-28. This entry recorded OPEN earlier the same day on a correct
      grep that returned one hit — the doc comment at GamaHostView.swift:53
      promising the adapter. PR #54 (f4c1ebc, merged 591134d) landed the
      adapter hours later and falsified it. The reading was sound; the tree
      moved underneath it, which is the failure mode a dated ledger exists to
      expose rather than hide. (The separate note stands: an earlier probe used
      an unquoted `--include`, which zsh failed to glob, so grep never ran —
      that non-result was never evidence.)
      Evidence now: Sources/GamaDraw/AccessibilitySnapshot.swift derives the
      snapshot platform-free from the rendered frame;
      Sources/GamaAppleUI/GamaHostAccessibility.swift is the real
      NSAccessibilityElement/UIAccessibilityElement adapter and posts
      .layoutChanged; 25 cases across
      Tests/gamaTests/{AccessibilitySnapshotTests,AppleHostAccessibilityTests}
      .swift, including "the published text is the frame's text, not a second
      model of it". PR #54's head passed all six hosted jobs (run 33141672035).
      Residual, unchanged and NOT to be upgraded: docs/Capabilities.md:26 keeps
      UIKit compile-proven only, and no manual VoiceOver/Rotor screen-reader
      acceptance pass has been performed.
- [x] Item 5: scale-aware `ProgressView`. Landed; verified 2026-08-28 by
      Tests/gamaTests/ProgressViewTests.swift, which pins the sub-cell
      boundary glyph at 1/8, keeps 0.99 visibly distinct from 1.0, refuses to
      read one ulp below 1 as full, and clamps NaN, ±infinity, negatives, and
      past-total values to the correct end.
- [x] Item 6: measure-first optimization of `CellBuffer.presentDiff` and
      `forEachRun`. CLOSED 2026-08-28 by PR #56 (merged f259247), whose exact
      head passed all six hosted jobs. The ordering held: the `gama-bench`
      harness and docs/Performance.md landed as commit 84a34b5 BEFORE the
      optimization in 9173d2f, so the number has a source.
      Outcome, and the interesting half: only ONE of the two named functions
      was optimized. `forEachRun` via `DrawList.from` went from ~90,834 ns to
      ~43,125 ns median (-52%, five alternating baseline/optimized release
      pairs, docs/Performance.md:94-102). `presentDiff` measured 7,042 ns — the
      CHEAPEST phase of the four — and was deliberately left untouched under
      the roadmap's own rule that only a measurement-identified hotspot may be
      optimized. docs/Performance.md:73-77 states it plainly: "The measurement
      contradicted the ledger item's own ordering."
      Read the -52% as "roughly halved under the recorded conditions", not as a
      constant: the doc's own baseline pairs range from 90,834 to 170,458 ns,
      and an independent run on the same machine measured 37,167 ns.
      Residual, unchanged: the harness asserts no threshold and is absent from
      scripts/check.sh, so it is evidence, not a gate. Allocation counts remain
      deliberately absent — nothing on Darwin counts them cumulatively, and
      Instruments is Task 5's tool.
- [ ] Item 7: `~Copyable` migration for `CellBuffer` and `Terminal`, including
      deinitialization tests. OPEN — verified 2026-08-28:
      GamaDraw/CellBuffer.swift:32 is `public struct CellBuffer: Hashable,
      Sendable` and both `Terminal` declarations in GamaTUI/Terminal.swift
      (:85 POSIX, :493 Windows) are ordinary copyable structs.
- [ ] Item 8: `StrictMemorySafety` and `InternalImportsByDefault`. OPEN —
      verified 2026-08-28: Package.swift enables only `MemberImportVisibility`
      among the relevant upcoming features.
- [x] Item 9: MLIR emitter unification with byte-for-byte deterministic
      fixture tests. CLOSED 2026-08-28 by PR #60, merged as
      `0deb07792c909b13cf86b68fd937bc3e278e8a2a`. The implementation head was
      `d5729eb60ca7a664c1ce42e0b66bcdeddf556fc2`. `GamaLowering` now
      routes structural and laid trees through one private recursive emitter
      without changing either public lowering entry point. `MLIRFixtureTests`
      contains 18 Swift Testing cases in one suite, and `--filter MLIR` matches
      22 tests across the new fixture suite and the preserved intent-level
      suite. All fourteen `RenderNode` cases pin structural and laid bytes.
      Canonicalization changes exactly two laid `gama.frame` expectations:
      fixed and flex frames now put dimensions before alignment, while
      structural bytes remain unchanged. `gama.divider` now emits `fg`, `bg`,
      and raw `sgr`, followed by its optional axis; the plain style remains
      `"default"`, `"default"`, and `0`. Layout distinctions remain deliberate:
      normal group layout becomes a top-leading `gama.overlay`, a hand-built
      laid group pins `gama.group`, and a nil-axis divider gains `axis = "v"`
      only through vertical-stack layout. The unmodified `scripts/check.sh`
      passed all thirteen fail-closed gates at that implementation head,
      including 248 Apple tests in 47 suites and the emulator runtime
      assertion, and ended with `OK — complete local Gama Framework acceptance
      matrix`. Hosted run
      [33219690659](https://github.com/donaldfilimon/gama/actions/runs/33219690659)
      passed all six ruleset-required jobs at that exact implementation head.
      The ledger-only final head
      `f11bff5cc92bbecb5f8514c658e2b631d10a6ab1` passed all six required jobs in
      hosted run
      [33220775849](https://github.com/donaldfilimon/gama/actions/runs/33220775849).
      Post-merge main run
      [33221629074](https://github.com/donaldfilimon/gama/actions/runs/33221629074)
      passed all six required jobs at the merge. Separately, Pages run
      [33221628954](https://github.com/donaldfilimon/gama/actions/runs/33221628954)
      passed the build, browser smoke, artifact upload, and deployment there.

## CI findings 2026-08-27 (evidence-backed, not yet fixed)
- [x] **Android emulator has never had KVM.** CLOSED 2026-08-28 by PR #52
      (merged b0de7d9), which added the android-emulator-runner README's udev
      rule as a step in the existing job — a step, not a job, so all six
      name-pinned contexts in ruleset 21626078 stayed intact (verified by
      diffing the `name:` lines against main). Proof, not inference: the job
      log now shows `crw-rw-rw- 1 root kvm 10, 232 /dev/kvm` and `disable Linux
      hardware acceleration: false`, and the `ProbeKVM: This user doesn't have
      permissions` line is gone. The Android job went from ~21 min and failing
      to **5m20s** passing. PR #52's exact head 46a8037 passed all six jobs,
      and main's post-merge acceptance run 33193668881 at b0de7d9 completed
      **green on all six** — which also closes the "no COMPLETED acceptance
      run" continuity worry recorded in goals.md.
      This finding had escalated before it was fixed: main's matrix was RED on
      its consequence (runs 33173171147 at 4556226 and 33171217505 at 591134d,
      Android job failing `adb: failed to install ...: Failure calling service
      package: Broken pipe
      (32)` three times). Original evidence, on a GREEN main run
      (33068264814, job 98503691390): `ProbeKVM: This user doesn't have
      permissions to use KVM (/dev/kvm)`, group empty (`kvm:x:993:`), falls back
      to TCG software emulation every run. `grep -ci 'kvm|udev|accel'
      .github/workflows/ci.yml` == 0, and PR #41 adds none. Boot 380,965 ms on a
      passing run vs 720,220 ms on a failing one — that spread is unaccelerated
      QEMU, not a transport glitch, and the `Can't find service: package`
      signature is a package manager that had not registered yet. Fix is the
      android-emulator-runner README's ~6-line Enable-KVM udev step. Posted on
      PR #41 (whose author owns that job) rather than opened as a conflicting
      PR. Consequence if true: much of the 900/720/840/240 partitioning stops
      being load-bearing. CORRECTS the repo's own "adb install flakes are infra,
      not product" framing in docs/Capabilities.md — that row now carries the
      retraction rather than the disproven claim.
- [x] **check-boundaries.sh cannot catch libm symbol references.** It greps
      `^import (Foundation|AppKit|UIKit|Darwin|Glibc|WinSDK|Synchronization)$`,
      so a bare `Double.rounded()` in GamaCore passes boundaries locally and
      only fails at link on the static-Linux/wasm products ("undefined reference
      to 'round'/'rint'/'trunc'/'ceil'/'floor'"). Hit live on PR #42's wave-2
      head. Closing the hole needs a link-or-symbol check for the portable
      targets, not another import grep.
      CLOSED 2026-08-28 (verification sweep — the work landed, the ledger was
      stale): `scripts/check-portable-symbols.sh` (5b945ba) is exactly that
      symbol check. It resolves `llvm-nm` from the pinned toolchain, scans
      `--undefined-only` on each portable target's emitted objects, and rejects
      the whole libm entry-point set plus Swift's `_roundSlowPath` precursor.
      Wired into three gates, not one: `check-boundaries.sh:85` (host objects),
      `check-linux.sh:22,42` (static-Linux), and `check-wasm.sh:23`. It ships
      the negative control the entry asked for —
      `Tests/Fixtures/PortableSymbols/Sources/RoundedRequiresLibm` is compiled
      by `check-boundaries.sh:90`, must FAIL the scan, and the failure must name
      `_roundSlowPath` or the gate errors out. Import-grep-only detection is no
      longer the boundary story.
- [x] **A merge silently deleted two gate variable definitions and left the
      Android gate dead.** Found and fixed 2026-08-28. `52e8277` ("Merge branch
      'main' into ci/android-readiness-deadline") took main's side of the
      region six lines above two newly added definitions, deleting
      GAMA_ANDROID_READINESS_DEADLINE_SECONDS and
      GAMA_ANDROID_READINESS_POLL_DELAY_SECONDS while keeping all five
      references. Under `set -u` the gate died at the first readiness probe in
      56 ms with exit 1 and **zero output**, because each test case redirects
      into a temp file the EXIT trap deletes — the CI log could never name the
      missing variable. This is the second time a merge on this repo resolved
      in favour of stale declarations (see the PR #11/#14 entry in goals.md);
      the difference is that this one was invisible.
      Fixed in PR #52. The durable part is not the restored defaults but the
      guard: a reference-versus-definition loop at the top of
      test-android-emulator-readiness.sh asserts that every GAMA_ANDROID_* name
      the gate reads is also defaulted in it. Mutation-verified against the
      broken 52e8277 script — it names both missing variables and exits 1,
      where the old code produced nothing. No new CI job, so no orphaned
      context.
- [x] **PR #43 reopened the rejected `leak:XCTest` suppression.** Its
      lsan-suppressions.supp has exactly one non-comment line, `leak:XCTest` —
      the pattern closed with PR #31 and rejected at todo.md:100, goals.md:208,
      and roadmap:94. It ships no negative control (diff is ci.yml + the .supp
      only), so a green matrix proves the suppression works, not that Gama leak
      coverage survived. Repaired on `main` by deleting the suppression and
      moving leak proof out of Swift Testing entirely: the direct executable's
      deliberately leaked GamaCore `Signal` must fail under hosted Linux LSan.

## Later sub-projects (each needs its own spec first)
- [x] Sub-project 2: plugin runtime + capability model — APPROVED
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
      CLOSED 2026-08-27 (verification sweep): the item's own condition —
      "the follow-up's own exact-head six-job matrix is green" — is met.
      The hardening follow-up merged as PR #37; its exact head b11297d
      passed all six hosted jobs plus Devin Review, and 9519c05 (the five
      named defect fixes) is an ancestor of main. The deferred sub-items
      inside this entry (Tier 2 dylib, Tier 3 out-of-process, `.network`,
      scope subsumption, manifest macros, discovery, persistence, live
      window teardown on uninstall) remain deferred scope, not open work
      under this item.
- [x] Sub-project 3: scene-first app shell, windowing, lifecycle — APPROVED;
      scene core integrated on main and the macOS shell is implemented/local-
      proven on its delivery branch. Keep open until the shell PR and its
      post-merge six-job matrix are green.
      design at docs/superpowers/specs/2026-08-27-scene-first-app-shell-design.md.
      Scene core/migration and macOS shell are separate green delivery slices;
      packaging's .app slice depends on both.
      CLOSED 2026-08-27 (verification sweep) with a recorded evidence
      substitution. PR #21 head ca95b220 passed all six hosted jobs. The
      literal post-merge run 33048001992 at 84b2f40 was CANCELLED by the
      workflow's concurrency group rather than failing, so the proof rides
      on green descendant main runs 33054689162 (3b4c83a) and 33056641869
      (18ea46e); `git merge-base --is-ancestor 84b2f40 18ea46e` confirms
      both contain the shell. PR #39 exists precisely to stop this
      cancellation failure mode; until it lands, cancelled-run substitution
      stays a named residual, not a silent one.
- [x] Sub-project 4: packaging & distribution — APPROVED
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

      CLOSED 2026-08-27 (verification sweep): the item's own stated
      condition — "the packaging PR and its six-job matrix are green" — was
      already satisfied and the ledger had simply not been updated. PR #32
      head 77e3160 passed all six hosted jobs plus Devin Review, and the
      post-merge main acceptance run 33054689162 at 3b4c83a is also green.
      Residuals unchanged and still honest: Developer ID notarization is
      credential-gated with no credentialed run, and the iconutil path has
      no icon source, so neither is claimed.
