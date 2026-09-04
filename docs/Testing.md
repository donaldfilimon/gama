# Testing

Gama tests are **Swift Testing only**. There is no XCTest target, no mixed
runner, and no new `import XCTest`. `swift test` runs the `GamaTests` module
under the pinned Swift 6.5-dev toolchain.

## How to run

Always `unset TOOLCHAINS` first. Prefer `swiftly run` so `.swift-version`
(`main-snapshot-2026-08-21`) selects the compiler. This tree is
FileProvider-managed: tests must use a scratch path outside iCloud.

```bash
unset TOOLCHAINS
swiftly run swift --version          # must report 6.5-dev
swiftly run swift test --scratch-path /private/tmp/gama-framework-swiftpm
swiftly run swift test --scratch-path /private/tmp/gama-framework-swiftpm --filter BuilderTests
```

Everyday local gate (debug + test + release):

```bash
unset TOOLCHAINS
./scripts/check-apple.sh
```

The check scripts still pin via `xcrun --toolchain org.swift.65202608211a`.
That is the same snapshot `swiftly run` selects. Do not invoke PATH `swift`
(swiftly shims without `swiftly run` can still be overridden by a stray
`TOOLCHAINS`).

## Layout

All suites live in `Tests/gamaTests/`:

| File | Suites |
| --- | --- |
| `gamaTests.swift` | Geometry, Style, Layout, View builder (including ZStack overlay vs group), Signal, Actions, Cell buffer, MLIR, DrawList, Cell painter, FrameHost |
| `ModernTests.swift` | DrawList codec hostility, CellPainter ↔ DrawList, Overflow-safe geometry |
| `FormControlTests.swift` | TextField, Toggle, ProgressView |
| `EmbedTests.swift` | Independent C-embed contexts |
| `MacroUsageTests.swift` | `@Component` / `@Reactive` / `#rgb` compile-and-render; reactive state lifetime across frames under keyboard and pointer activation |
| `MacroExpansionTests.swift` | Macro expansion via `SwiftSyntaxMacrosGenericTestSupport` (no XCTest): `ReactiveSlot` peer and binding `render(in:)` expansion, `@Reactive` outside `@Component` and hand-written `render(in:)` diagnostics |
| `ViewStateIdentityTests.swift` | Per-surface `@Reactive` storage: inline persistence, `WindowGroup` independence, hoisted-instance per-surface writes, branch-flip eviction, out-of-band invalidation, `transientStateIDs`, `stateScope`, host-less local storage |
| `EmbedABITests.swift` | Embed ABI additions: `gama_embed_v1_abi_version`, hostile-resize clamps, frame-storage reuse |
| `WASMSerializerTests.swift` | WASM HTML serializer (compiled off wasm32) |
| `AppleHostTests.swift` | Embeddable AppKit host (macOS only) |
| `AppleShellTests.swift` | Offscreen AppKit scene/window ownership (macOS only) |
| `POSIXTerminalIntegrationTests.swift` | PTY raw-mode restore (Darwin) |
| `WindowsTerminalTests.swift` | Native console translators (Windows only) |

## Conventions

- `@Suite("…")` + `@Test("…")`. Prefer `#expect` over `Issue.record` except
  when a `guard case` must exit early.
- Observer counters use a file-local `@unchecked Sendable` box. Do not add
  `nonisolated(unsafe)` in GamaCore; tests may, but the box is the default.
- Macro expansion tests call `assertMacroExpansion` from
  `SwiftSyntaxMacrosGenericTestSupport` with a `failureHandler` that records
  a Swift Testing `Issue`. Do not reintroduce `SwiftSyntaxMacrosTestSupport`
  (it imports XCTest).
- Platform suites stay behind `#if canImport(AppKit)`, `#if canImport(Darwin)`,
  `#if os(Windows)`.
- New tests go in Swift Testing. There is no XCTest fallback.

## Linux sanitizers

The Linux job separates two contracts which cannot honestly share a process:

- `swift test --sanitize address` retains broad address-safety coverage, with
  `detect_leaks=0` only because SwiftPM's generated runner loads an XCTest
  harness that retains process-lifetime suite metadata.
- `scripts/check-linux-leaks.sh` builds `gama-leak-check` with ASan and runs
  the executable directly under `detect_leaks=1`. The clean path constructs,
  pumps, and destroys a real `FrameHost` without Swift Testing or XCTest. The
  same binary's `--deliberate-leak` path intentionally retains a GamaCore
  `Signal`; CI requires LeakSanitizer's exact configured failure code and
  diagnostic before the gate can pass. No suppression file is involved.

LeakSanitizer leak detection is unsupported on Darwin. macOS can prove that
the executable builds and its clean lifecycle runs, but only the hosted Linux
job can prove both the clean LSan result and the failing negative control.
