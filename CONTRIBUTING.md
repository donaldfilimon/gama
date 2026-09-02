# Contributing to Gama

## Toolchain

The compiler is a pinned Swift 6.5-dev main snapshot selected by
`.swift-version`; `Toolchains.toml` is the pin authority and
`scripts/check-toolchain-pins.sh` fails on any drift. Always:

```bash
unset TOOLCHAINS
swiftly run swift build
swiftly run swift test --scratch-path /private/tmp/gama-framework-swiftpm
```

Details and traps (iCloud checkout, Windows exception): `docs/Toolchain.md`.

## Gate reference

`./scripts/check.sh` runs the full local acceptance matrix — thirteen gates,
sequential, fail-closed. Do not weaken or skip a gate to make it green.

| Gate | Proves | Hosted CI job / step |
| --- | --- | --- |
| `check-apple.sh` | Debug build, full test suite, release build on the pinned snapshot | macOS — "Core, macros, POSIX TUI, Apple UI" |
| `check-apple-platforms.sh` | iOS/tvOS/visionOS compile via xcodebuild | macOS — "iOS, tvOS, and visionOS compile" |
| `check-boundaries.sh` | GamaCore import bans, no process-global state, tools-version pin; chains `check-toolchain-pins.sh` | macOS — "Source boundaries and documentation" |
| `check-concurrency-negative.sh` | Host-confined types cannot cross `Sendable` boundaries | macOS — "Source boundaries and documentation" |
| `check-c-abi.sh` | C consumer compiles against `GamaEmbed.h` with -Werror, links `libGamaEmbed.a`, runs | Linux — "C ABI consumer compile, link, and run" |
| `check-embedded.sh` | Embedded-Swift whole-module compile + relocatable link of GamaCore at the exact snapshot | Embedded job |
| `check-linux.sh` | Static Linux SDK cross-compile | Linux — "Static Linux SDK" |
| `check-wasm.sh` | WASM SDK build + Node and headless-Chrome runtime smokes | WebAssembly job |
| `check-android.sh` | Android SDK cross-compile + JNI packaging | Android — "Cross-compile GamaEmbed" |
| `check-android-emulator.sh` | API 36 emulator input/frame round trip | Android — "Required emulator input/frame round trip" |
| `check-mlir.sh` | Emitted dialect parses under `mlir-opt --allow-unregistered-dialect` | macOS — "MLIR parse" |
| `check-docs.sh` | DocC builds with zero warnings; Capabilities ledger present with its status legend | macOS — "Source boundaries and documentation" |
| `check-doc-coverage.sh` | Every public declaration has a symbol-graph doc comment, excluding only justified allowlist entries | macOS — "Source boundaries and documentation" |

The Linux job additionally runs the native test suite under Address and
Thread Sanitizer; the Windows job runs the console smoke on Swift 6.4.x (the
documented exception). Gates that need a pinned SDK or another OS fail
locally by design — the hosted matrix is their proof.

## Claim-honesty policy

`docs/Capabilities.md` is the evidence ledger; its status vocabulary
(Implemented / Locally proven / Hosted proven / Provisional / Blocked) is
the only sanctioned wording. Never document unproven capability as shipped,
and never state a proof a gate does not actually perform.

## Workflow

Prefer small reviewable commits, each verified by the relevant gate before
committing (gated slices). Preserve `Package.resolved`. Never force-push the
default branch. Merge only after the required hosted matrix is green — a red
or still-running matrix is a blocker, not a formality. Design specs go under
`docs/superpowers/specs/` (drafts carry open questions and are not
commitments); the running ledger is `tasks/goals.md` + `tasks/todo.md`.
