## Learned User Preferences

- Build and test with `unset TOOLCHAINS` then `/Users/donaldfilimon/.grok/skills/swift/scripts/xcode-swift.sh` (`build` / `test`); never use PATH `swiftly` or DEVELOPMENT-SNAPSHOT toolchains.
- Prefer attaching `/swift` for toolchain-sensitive work; follow "do all" / "continue" as broaden-and-keep-going, not stop-at-green.
- Primary UX is SwiftUI wrapping Qt (`QtPanelView` / bridge), not a standalone Qt `QApplication` window as the default shell.
- Keep `CGamaQt` as a header-oriented clang module for Swift C++ interop (implementations in headers / `detail/`; SPM stub `.cpp` only if required).

## Learned Workspace Facts

- `/Users/donaldfilimon/Projects/Gama` is a SwiftPM macOS package (Swift 6.4 / C++23 `.cxx2b`, Cxx interop): executable `Gama` under `Sources/Gama/`, Qt bridge target `CGamaQt` under `Sources/CGamaQt/` — distinct from `~/Public/Gama/`.
- `CGamaQt` layout: public `include/GamaQt.hpp` for Swift; implementations in `detail/*.hpp`; minimal `.cpp` stub that includes detail headers for SPM.
- Homebrew Qt defaults to `/opt/homebrew` (override with `QT_PREFIX`); package links QtCore/Gui/Widgets/Network frameworks plus JavaScriptCore; platform floor is macOS v27 (Liquid Glass + FoundationModels smart search).
- Avoid `QStringLiteral` with raw string literals (breaks `qMakeStringPrivate`); use `QString::fromUtf8(R"(...)")` or equivalent at that boundary.
- Prefer `std::string` by value (not `string_view`) at the Swift/C++ API boundary so interop owns a stable buffer.
