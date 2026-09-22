# Gama Qt engineering guide

This file is the canonical agent guide for this repository; `CLAUDE.md` points here.

## What this is

`~/dev/active/gama-qt` is a local-only SwiftPM macOS package: a SwiftUI/SwiftData browser shell backed by a Swift/C++23 bridge to Qt 6. It is distinct from the Swift framework at `~/Desktop/Gama` (`donaldfilimon/gama`).

- Primary UX is SwiftUI wrapping Qt (`QtPanelView` / bridge), not a standalone Qt `QApplication` window as the default shell. `--legacy-browser` is a Qt Widgets bridge demonstration, not the product shell.
- CoreAI smart search (FoundationModels) degrades to deterministic URL/search heuristics when the on-device model runtime is unavailable.

## Toolchain and gate

- Swift 6.4, C++23 (`.cxx2b`), Cxx interop, platform floor macOS v27 (Liquid Glass + FoundationModels smart search).
- Build and test with `unset TOOLCHAINS` then `/Users/donaldfilimon/.grok/skills/swift/scripts/xcode-swift.sh` (`build` / `test`). Never use PATH `swiftly` or DEVELOPMENT-SNAPSHOT toolchains. The script is `exec /usr/bin/xcrun --toolchain default swift "$@"`, so every `swift` flag passes through.
- **Gate: `Scripts/check.sh`.** It runs `build` then `test` through `xcode-swift.sh` (override the path with `XCODE_SWIFT`; falls back to `xcrun swift` when the wrapper is absent), echoes `build EXIT:<n>` and `test EXIT:<n>`, and exits nonzero if either failed. Redirect it to a log and read the exit code from the script, not from a pipe.
- Single test: `~/.grok/skills/swift/scripts/xcode-swift.sh test --filter GamaTests` (whole target) or `... test --filter heuristicHomeAliases` (one `@Test` function). `Tests/GamaTests` declares no `@Suite`, so filter by target or function name.
- Run: `Scripts/run.sh [args…]` unsets `TOOLCHAINS`, builds `--product Gama --disable-sandbox` through `xcode-swift.sh` (falls back to `xcrun swift build`), then execs the built `Gama` binary with argv forwarded (Xcode `swift run` drops args).
- Homebrew Qt defaults to `/opt/homebrew` (override with `QT_PREFIX`); the package links the QtCore/Gui/Widgets/Network frameworks plus JavaScriptCore.

## Layout

Four targets:

- `Sources/Gama/`: executable `Gama` (SwiftUI app, bridge wrappers, CoreAI search).
- `Sources/CGamaQt/`: Qt bridge target. Public `include/GamaQt.hpp` is the Swift-facing clang module; implementations live in `detail/*.hpp`; `CGamaQt.cpp` is the minimal SPM stub that includes the detail headers.
- `Sources/GamaCore/`: library, pure Swift, no Qt and no Cxx. Qt-free logic such as `AddressResolver.swift` belongs here. `Tests/GamaTests/LayeringTests.swift` fails if any `GamaCore` source imports `CGamaQt` or mentions `Qt`.
- `Tests/GamaTests/`: Swift Testing. `AddressResolverTests.swift` covers `GamaCore`, `GamaTests.swift` covers the `CGamaQt` bridge; tests for either target belong here.

## Traps

- Keep `CGamaQt` a header-oriented clang module for Swift C++ interop (implementations in headers / `detail/`; an SPM stub `.cpp` only if required).
- Avoid `QStringLiteral` with raw string literals (breaks `qMakeStringPrivate`); use `QString::fromUtf8(R"(...)")` or equivalent at that boundary.
- Prefer `std::string` by value (not `string_view`) at the Swift/C++ API boundary so interop owns a stable buffer.

## Working preferences

- Prefer attaching `/swift` for toolchain-sensitive work.
- Treat "do all" / "continue" as broaden-and-keep-going, not stop-at-green.

<!-- machine-git-policy -->
## Git workflow (machine policy, 2026-08-27)

Work on the default branch in this canonical checkout. Do not create
branches or worktrees by default; they are for tasks that genuinely need
isolation, or when Donald asks. Any worktree or topic branch created here
must be merged back into this checkout's default branch, the worktree
removed, and the branch deleted, before pushing and before the task is
called done. Full policy: `~/.claude/CLAUDE.md` (*Git discipline*).
<!-- /machine-git-policy -->
