# Goals

## Ship the Swift 6.4 Gama Framework

status: done

- Apple Swift 6.4 debug, 73 tests, release, and iOS/tvOS/visionOS compile:
  locally green.
- Portable core, macros, drawing, TUI, Apple UI, C ABI, WASM, MLIR, and Qt
  adapter sources: implemented; Qt 6.11 and MLIR parser gates are locally green.
- Exact 2026-08-14 Swift 6.4 snapshot and matching Linux, WASM, and Android
  SDKs: checksum-pinned and locally installed; Linux, WASM runtime, Android
  arm64/x86_64 cross-build, JNI packaging, API 36 emulator input/frame round
  trip, and Embedded compile/link gates pass.
- Hosted Linux, Windows, WASM, Android/emulator, and required PR checks: pending.
- Merge is forbidden until the required matrix is green.
- Outcome: merged as PR #6; hosted "Gama acceptance" matrix green on main at
  f509e2c (2026-08-24). Superseded going forward by the umbrella goal below
  (6.5-dev snapshot, Qt adapter removed 2026-08-26).

## Build the Gama umbrella application framework

status: in_progress

- Intention (Donald, 2026-08-26): a cross-platform, macro/plugin-based
  UI/UX/application framework in Swift — Tauri/React-Native-class — spanning
  WASM, Windows, macOS desktop, Embedded, and more, with the retained-IR
  renderer as the foundation (own-the-rendering decision).
- Sub-project 1 (foundation) Current: DONE. Canonical checkout adopted at
  ~/Desktop/Gama on the donaldfilimon/gama history; migrated to swiftly
  main-snapshot-2026-08-21 (Swift 6.5-dev); Qt adapter removed; all eight
  local gates green; full hosted matrix green (Linux/macOS/WASM/Embedded/
  Android on 6.5-dev, Windows on 6.4.x — see exception below); merged as
  PR #7 (74e77df on main, 61 commits); dev/active/gama-swift retired to
  dev/archive/gama-swift-superseded-2026-08-26 after verifying zero unique
  commits/stashes; ~/CLAUDE.md corrected.
- Windows exception (Current, honest residual): swift.org has published no
  Windows main-development snapshot since 2026-05-20-a, so the Windows job
  runs the proven 6.4.x 2026-08-14-a installer. Windows is NOT yet verified
  on 6.5-dev; revisit when swift.org resumes Windows main snapshots.
- Sub-projects 2-4 Proposed: drafts written and committed under
  docs/superpowers/specs/drafts/ (plugin runtime + capability model; app
  shell/windowing/lifecycle; packaging & distribution). Each is DRAFT ONLY —
  no code, no approval — and ends with open questions Donald must decide
  before its spec is finalized. Foundation spec:
  docs/superpowers/specs/2026-08-26-gama-umbrella-foundation-design.md
