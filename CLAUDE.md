# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Read `AGENTS.md` — it is the canonical, up-to-date guide for this repo (stack, commands, architecture, gotchas). Follow it exactly.

Quick anchors:
- **Stack**: SwiftPM macOS package (Swift 6.4 / C++23 `.cxx2b`, Cxx interop) — executable `Gama` under `Sources/Gama/`, Qt bridge target `CGamaQt` under `Sources/CGamaQt/`, pure-Swift library `GamaCore` under `Sources/GamaCore/`, tests in `Tests/GamaTests/`; Homebrew Qt at `/opt/homebrew` (override `QT_PREFIX`); macOS v27 floor.
- Build/test: `unset TOOLCHAINS` then `/Users/donaldfilimon/.grok/skills/swift/scripts/xcode-swift.sh build` / `... test` — never PATH `swiftly` or DEVELOPMENT-SNAPSHOT toolchains.
- Single test: `... xcode-swift.sh test --filter GamaTests` (target) or `... test --filter heuristicHomeAliases` (one `@Test`; `Tests/GamaTests` has no `@Suite`s).
- Run: `Scripts/run.sh [args…]` — builds `--product Gama --disable-sandbox` via `xcode-swift.sh` and execs the binary with argv forwarded.
- Primary UX is SwiftUI wrapping Qt (`QtPanelView` / bridge), not a standalone Qt `QApplication` window.
- Keep `CGamaQt` header-oriented (`include/GamaQt.hpp` public, impls in `detail/*.hpp`, minimal `.cpp` stub); avoid `QStringLiteral` with raw string literals; pass `std::string` by value (not `string_view`) at the Swift/C++ boundary.

<!-- machine-git-policy -->
## Git workflow (machine policy, 2026-08-27)

Work on the default branch in this canonical checkout. Do not create
branches or worktrees by default; they are for tasks that genuinely need
isolation, or when Donald asks. Any worktree or topic branch created here
must be merged back into this checkout's default branch, the worktree
removed, and the branch deleted, before pushing and before the task is
called done. Full policy: `~/.claude/CLAUDE.md` (*Git discipline*).
<!-- /machine-git-policy -->
