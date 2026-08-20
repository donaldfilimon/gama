# gama

SwiftPM TUI framework: retained `ViewNode` tree + result builders (`GamaCore`), POSIX/ANSI backend (`GamaTUI`), and `gama demo` showcase.

## Current vs Proposed

| Capability | Status | Proof |
|------------|--------|--------|
| `GamaCore` view tree, layout, paint, `Engine` | **Current** | `GamaCoreTests` (virtual `CellGrid`, no TTY) |
| `GamaTUI` ANSI + key/mouse parse | **Current** | `GamaTUITests` |
| `gama demo` CLI | **Current** | `gamaTests` + live TTY (`gama demo`) |
| Embedded compile of `GamaCore` | **Current** | `./scripts/check-embedded.sh` object file |
| GUI / windowed UI | **Proposed** | Not in this tree |
| Compiler-plugin macros | **Proposed** | Result builders are the DSL; they are not macros |
| MLIR / SwiftIR | **Proposed** | Not a UI renderer |
| MCU flash / on-device UI | **Proposed** | Compile gate only |
| Linux TUI CI | **Proposed** | POSIX may work; unproven here |
| Windows console | **Proposed** | Out of v1 |

A green Gate A does **not** prove Embedded. A green Gate B does **not** prove a live TUI. Do not write **Current** for GUI, macros, MLIR, or MCU.

## Commands

| What | Command | Notes |
|------|---------|-------|
| Gate A (macOS TUI) | `./scripts/check.sh` | Unsets `TOOLCHAINS`; XcodeDefault `swift build` + `swift test` |
| Gate B (Embedded `GamaCore`) | `./scripts/check-embedded.sh` | OSS snapshot `swiftc` + `-enable-experimental-feature Embedded` |
| Run demo | `unset TOOLCHAINS; /usr/bin/xcrun --toolchain default swift run gama demo` | Needs a TTY; q / Ctrl-C / Quit restores the terminal |

Do **not** use PATH `swift` for Gate A (swiftly 6.5-dev).

## Architecture

```
AppState → @ViewBuilder → ViewNode
  → Layout.layout → Paint into CellGrid
  → GamaTUI ANSI diff

TTY bytes → Event → Engine.handle → Action → reduce → rebuild
```

```
Sources/GamaCore/   # stdlib only; no Foundation, no POSIX
Sources/GamaTUI/    # Darwin termios + ANSI; depends on GamaCore
Sources/gama/       # ArgumentParser CLI + DemoApp
```

`GamaCore` must not `import Foundation`. Heap is allowed (`indirect` `ViewNode`).

## Toolchain

- **Gate A:** Xcode 6.4 via `/usr/bin/xcrun --toolchain default swift`. `swift-tools-version: 6.4`. `.swift-version` is `xcode`.
- **Gate B:** `swift-DEVELOPMENT-SNAPSHOT-2026-08-11-a` (override with `GAMA_EMBEDDED_TOOLCHAIN`). Xcode 6.4 cannot load an Embedded stdlib. This is a documented exception.

## Style

- Swift Testing (`@Test` / `#expect`), not XCTest
- App owns state; no `@State` / `any View`
- Interactive widgets take an explicit `NodeID`
- Keep `CLAUDE.md` a thin redirect to this file

## Workflow

- Use both gates before claiming the v1 slice works.
- Do not init a git remote or push unless asked.
