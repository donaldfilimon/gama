# Gama Qt

Gama Qt is the native SwiftUI/SwiftData browser shell backed by a Swift/C++23
bridge to Qt 6. The primary experience is a macOS window with tabs, sidebar,
WebKit content, an embedded Qt panel, and optional on-device CoreAI-assisted
address resolution. The `--legacy-browser` path exists as a Qt Widgets bridge
demonstration; it is not the default product shell.

This package lives at `qt/` inside the `donaldfilimon/gama` repository (folded
in on 2026-09-28 from the former local-only `~/dev/active/gama-qt` checkout,
history preserved). It is a separate SwiftPM package from the enclosing Gama
framework: it does not depend on it and is not built by the framework's gates.

## Requirements

- macOS 27 and Xcode 27
- the machine Xcode Swift wrapper documented in `AGENTS.md`
- Homebrew Qt 6 at `/opt/homebrew` by default; set `QT_PREFIX` to override it

## Build and test

The gate is `Scripts/check.sh`: it runs `build` then `test` through the
wrapper, prints `build EXIT:<n>` and `test EXIT:<n>`, and exits nonzero if
either failed. Redirect it to a log rather than piping it.

```bash
cd ~/dev/active/Gama/qt
Scripts/check.sh >| /tmp/gama-qt-check.log 2>&1; echo EXIT:$?
```

The same steps by hand:

```bash
unset TOOLCHAINS
/Users/donaldfilimon/.grok/skills/swift/scripts/xcode-swift.sh build
/Users/donaldfilimon/.grok/skills/swift/scripts/xcode-swift.sh test
```

The package exposes the `Gama` executable and the pure-Swift `GamaCore`
library. `CGamaQt` is a header-oriented Clang module: its public bridge lives in
`Sources/CGamaQt/include/GamaQt.hpp`, with implementations under `detail/`.

## Run

`Scripts/run.sh` builds the `Gama` product with the supported wrapper and execs
the built binary with arguments forwarded (Xcode `swift run` drops them). The
Qt runtime search path comes from the package itself: `Package.swift` links
with `-rpath $QT_PREFIX/lib`.

```bash
Scripts/run.sh                 # SwiftUI browser
Scripts/run.sh --help          # CLI and shortcut reference
Scripts/run.sh Donald          # Swift-to-C++ owned-string smoke
Scripts/run.sh --callback      # C++-to-Swift callback smoke
Scripts/run.sh --legacy-browser
```

CoreAI smart search degrades to deterministic URL/search heuristics when the
Foundation Models runtime is unavailable.

## Verification status

Verified locally on 2026-09-22 (Xcode 27.2, Swift 6.4, Homebrew Qt 6.11.2):
`Scripts/check.sh` passed with all 16 Swift Testing tests, and the help,
owned-string greeting, and callback CLI paths completed successfully. Those
checks cover the bridge and deterministic address behavior. Interactive
WebKit/Qt embedding and on-device model output remain manual UI/runtime
acceptance layers.
