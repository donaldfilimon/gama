## Learned User Preferences

- Build and test with `unset TOOLCHAINS` then `/Users/donaldfilimon/.grok/skills/swift/scripts/xcode-swift.sh` (`build` / `test`); never use PATH `swiftly` or DEVELOPMENT-SNAPSHOT toolchains. The script is `exec /usr/bin/xcrun --toolchain default swift "$@"`, so every `swift` flag passes through.
- Single test: `~/.grok/skills/swift/scripts/xcode-swift.sh test --filter GamaTests` (whole target) or `... test --filter heuristicHomeAliases` (one `@Test` function). `Tests/GamaTests` declares no `@Suite`, so filter by target or function name.
- Run: `Scripts/run.sh [args…]` unsets `TOOLCHAINS`, builds `--product Gama --disable-sandbox` through `xcode-swift.sh` (falls back to `xcrun swift build`), then execs the built `Gama` binary with argv forwarded (Xcode `swift run` drops args).
- Prefer attaching `/swift` for toolchain-sensitive work; follow "do all" / "continue" as broaden-and-keep-going, not stop-at-green.
- Primary UX is SwiftUI wrapping Qt (`QtPanelView` / bridge), not a standalone Qt `QApplication` window as the default shell.
- Keep `CGamaQt` as a header-oriented clang module for Swift C++ interop (implementations in headers / `detail/`; SPM stub `.cpp` only if required).

## Learned Workspace Facts

- `~/dev/active/gama-qt` is a SwiftPM macOS package (Swift 6.4 / C++23 `.cxx2b`, Cxx interop) with four targets: executable `Gama` under `Sources/Gama/`; Qt bridge target `CGamaQt` under `Sources/CGamaQt/`; library `GamaCore` under `Sources/GamaCore/` (pure Swift, no Qt or Cxx — Qt-free logic such as `AddressResolver.swift` belongs here); and `Tests/GamaTests` (Swift Testing; `AddressResolverTests.swift` covers `GamaCore`, `GamaTests.swift` covers the `CGamaQt` bridge — tests for either target belong here).
- `CGamaQt` layout: public `include/GamaQt.hpp` for Swift; implementations in `detail/*.hpp`; minimal `.cpp` stub that includes detail headers for SPM.
- Homebrew Qt defaults to `/opt/homebrew` (override with `QT_PREFIX`); package links QtCore/Gui/Widgets/Network frameworks plus JavaScriptCore; platform floor is macOS v27 (Liquid Glass + FoundationModels smart search).
- Avoid `QStringLiteral` with raw string literals (breaks `qMakeStringPrivate`); use `QString::fromUtf8(R"(...)")` or equivalent at that boundary.
- Prefer `std::string` by value (not `string_view`) at the Swift/C++ API boundary so interop owns a stable buffer.

<!-- machine-git-policy -->
## Git workflow (machine policy, 2026-08-27)

Work on the default branch in this canonical checkout. Do not create
branches or worktrees by default; they are for tasks that genuinely need
isolation, or when Donald asks. Any worktree or topic branch created here
must be merged back into this checkout's default branch, the worktree
removed, and the branch deleted, before pushing and before the task is
called done. Full policy: `~/.claude/CLAUDE.md` (*Git discipline*).
<!-- /machine-git-policy -->
