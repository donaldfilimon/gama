# Gama umbrella — foundation design (sub-project 1)

Date: 2026-08-26. Status: approved (session decisions by Donald).

## Goal

Turn Gama into a cross-platform, macro/plugin-based application framework
(Tauri/React-Native-class) in Swift. This spec covers sub-project 1 only:
the foundation the later work builds on.

## Decisions (locked)

1. **Render model: own the rendering.** The existing retained pipeline is
   the foundation: views → `RenderNode` IR (`GamaCore`) → `DrawList`
   (`GamaDraw`) → TUI / AppleUI / WASM / Embed / MLIR backends. No webview
   foundation, no native-widget mapping.
2. **Location:** the canonical checkout is `~/Desktop/Gama` (iCloud-managed;
   mitigations are baked into scripts and CLAUDE.md rather than left to
   memory).
3. **One `Package.swift`, no Qt.** The `Adapters/GamaQt` adapter and its
   gate/CI step are removed. `~/dev/active/gama-qt` (a Qt browser app) stays
   untouched and out of scope. All new code lands in this repository.
4. **History: adopt `donaldfilimon/gama` wholesale.** 56 commits, remote,
   and CI came along; new work commits on top. The old `~/dev/active/
   gama-swift` checkout is retired after `main` is green and pushed.
5. **Toolchain: swiftly `main-snapshot-2026-08-21`** (Apple Swift 6.5-dev,
   toolchain id `org.swift.65202608211a`), pinned in `.swift-version`.
   Manifest stays tools-version 6.4 (Xcode's SwiftPM must still resolve it
   for xcodebuild platform gates; nothing needs 6.5 grammar). Spike-verified 2026-08-26: full build + 18 tests /
   6 suites pass, macros included, existing swift-syntax pin unchanged.
   The pin bumps only deliberately (a needed compiler feature or fix), and
   local + CI move together.

## Sub-project decomposition (later specs)

2. Plugin runtime + capability model — runtime extension points; must not
   break GamaCore's zero-runtime-dependency property.
3. App shell — window/lifecycle management per platform on top of
   `FrameHost`.
4. Packaging & distribution — .app/.exe/wasm bundle/embedded static lib.

## Sub-project 1 scope

Adoption (done at spec time), 6.5-dev migration, Qt removal, iCloud-safe
local gates, CI migration to the main-snapshot family across five of the six
jobs (macOS, Linux native+sanitizers+static SDK, WASM, Android+emulator,
Embedded); Windows stays on 6.4.x per the exception below. No new framework
code.

## Platform exception

Windows: swift.org has published no Windows main-development snapshot since
2026-05-20-a, so the Windows CI job stays on the newest proven 6.4.x branch
snapshot (2026-08-14-a) until main-snapshot publishing resumes. All other
jobs run the pinned main snapshot.

## Risks

- swift.org snapshot artifact availability differs per platform per date;
  CI pins whatever main-snapshot date has ALL required artifacts, and
  `.swift-version` matches it.
- `swiftlang/swift-syntax` fetch returned 403 from this machine during the
  spike (local SwiftPM cache satisfied resolution). CI runners fetch
  directly; if a runner ever 403s, mirror the pinned revision.
