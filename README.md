# Gama Qt

Gama Qt is the native SwiftUI/SwiftData browser shell backed by a Swift/C++23
bridge to Qt 6. The primary experience is a macOS window with tabs, sidebar,
WebKit content, an embedded Qt panel, and optional on-device CoreAI-assisted
address resolution. The `--legacy-browser` path exists as a Qt Widgets bridge
demonstration; it is not the default product shell.

This checkout is the canonical local `gama-qt` project. It is distinct from the
Swift framework at `~/Desktop/Gama`.

## Requirements

- macOS 27 and Xcode 27
- the machine Xcode Swift wrapper documented in `AGENTS.md`
- Homebrew Qt 6 at `/opt/homebrew` by default; set `QT_PREFIX` to override it

## Build and test

```bash
cd ~/dev/active/gama-qt
unset TOOLCHAINS
/Users/donaldfilimon/.grok/skills/swift/scripts/xcode-swift.sh build
/Users/donaldfilimon/.grok/skills/swift/scripts/xcode-swift.sh test
```

The package exposes the `Gama` executable and the pure-Swift `GamaCore`
library. `CGamaQt` is a header-oriented Clang module: its public bridge lives in
`Sources/CGamaQt/include/GamaQt.hpp`, with implementations under `detail/`.

## Run

`Scripts/run.sh` builds with the supported wrapper, supplies the Qt runtime
search path, and forwards arguments:

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

Verified locally on 2026-08-27: the supported wrapper build passed, all 9 Swift
Testing tests passed, and the help, owned-string greeting, and callback CLI
paths completed successfully. Those checks cover the bridge and deterministic
address behavior. Interactive WebKit/Qt embedding and on-device model output
remain manual UI/runtime acceptance layers.
