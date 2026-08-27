# Gama documentation index

Start here. Every guide opens with a status line using the vocabulary defined
in [Capabilities.md](Capabilities.md#status-vocabulary); no document may
describe a blocked capability as shipped.

## Project-wide

- [Toolchain.md](Toolchain.md) — the pinned Swift 6.5-dev snapshot, why the
  tools-version stays 6.4, the Windows exception, and `swiftly run` usage.
- [Testing.md](Testing.md) — Swift Testing-only policy, suite map, and
  invocation (scratch path rules included).
- [Capabilities.md](Capabilities.md) — the evidence ledger: what each
  capability's proof actually is, and what proof is still required.
- [MLIRDialect.md](MLIRDialect.md) — the `gama` dialect op reference.
- [../CONTRIBUTING.md](../CONTRIBUTING.md) — gates, CI mapping, claim-honesty
  policy, and the gated-slice workflow.

## Backend guides

- [backends/TUI.md](backends/TUI.md) — terminals (POSIX + Windows console).
- [backends/AppleUI.md](backends/AppleUI.md) — AppKit/UIKit embedding.
- [backends/AppleShell.md](backends/AppleShell.md) — macOS application and
  multi-window ownership.
- [backends/WASM.md](backends/WASM.md) — browser hosting via `WebHost/`.
- [backends/CEmbed.md](backends/CEmbed.md) — the C ABI, walkthrough included.
- [backends/Android.md](backends/Android.md) — JNI packaging and the emulator
  gate.

## Decisions and design

- [adr/](adr/0000-index.md) — architecture decision records.
- [superpowers/specs/](superpowers/specs/) — full design specs; `drafts/`
  holds unreviewed proposals with open questions (not commitments).

Symbol-level API documentation lives in `Sources/GamaCore/GamaCore.docc`
(built by `scripts/check-docs.sh` with warnings as errors) and as `///`
comments on every public declaration in every target.
