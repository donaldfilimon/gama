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

## Code follow-ups from Codex review of PR #10 (docs narrowed in f0078dc;
## behavior itself unchanged — each needs a code PR with tests)
- [ ] P1: ZStack(.topLeading) lowers to the exact overlay shape
      flattenChildren uses as its tuple sentinel, so stack/List parents
      flatten its children instead of layering. Needs a distinct sentinel
      or discriminator. (Primitives.swift ZStack.render / View.swift
      flattenChildren)
- [ ] Border title: measure reserves displayWidth+4 but painter requires
      strictly-wider frame — natural-size bordered views reserve blank
      space and drop the caption (CellPainter.drawBorder).
- [ ] Divider in a square (1x1) frame renders the horizontal glyph even
      inside an HStack; carry the stack axis into the node or break ties.
- [ ] TextField appends control characters (e.g. "\n" via the C embed
      input path) — decide filter-or-allow and test it.
- [ ] TextLayout wide table misses emoji-presentation scalars outside the
      hard-coded ranges (e.g. U+231A) — extend or keep the documented
      subset deliberately.
- [ ] Button focus style: deeper label styles win over the focus wrap
      (custom-colored labels keep their colors when focused) — confirm
      intended or invert precedence.

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
