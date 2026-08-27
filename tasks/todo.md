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
- [ ] DocC catalogs exist only for GamaCore (7 articles); GamaDraw and the
      backends have none. Adding catalogs requires extending check-docs.sh,
      which hardcodes the GamaCore symbol-graph/catalog paths.
- [ ] check-docs.sh's Capabilities.md grep is tautological (matches the
      table header "Current evidence"); tighten if a stronger claim-honesty
      check is wanted.

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
