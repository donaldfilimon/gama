# Goals

## Ship the Swift 6.4 Gama Framework

status: in_progress

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
