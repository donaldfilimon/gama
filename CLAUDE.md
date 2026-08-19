# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Read `AGENTS.md` — it is the canonical, up-to-date guide for this repo (stack, commands, architecture, gotchas). Follow it exactly.

Quick anchors:
- **Stack**: SwiftPM macOS package (Swift 6.4 / C++23 `.cxx2b`, Cxx interop) — executable `Gama` under `Sources/Gama/`, Qt bridge target `CGamaQt` under `Sources/CGamaQt/`; Homebrew Qt at `/opt/homebrew` (override `QT_PREFIX`); macOS v27 floor.
- Build/test: `unset TOOLCHAINS` then `/Users/donaldfilimon/.grok/skills/swift/scripts/xcode-swift.sh build` / `... test` — never PATH `swiftly` or DEVELOPMENT-SNAPSHOT toolchains.
- Primary UX is SwiftUI wrapping Qt (`QtPanelView` / bridge), not a standalone Qt `QApplication` window.
- Keep `CGamaQt` header-oriented (`include/GamaQt.hpp` public, impls in `detail/*.hpp`, minimal `.cpp` stub); avoid `QStringLiteral` with raw string literals; pass `std::string` by value (not `string_view`) at the Swift/C++ boundary.
