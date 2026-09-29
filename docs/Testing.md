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
swiftly run swift test --scratch-path /private/tmp/gama-framework-swiftpm --filter ViewBuilderTests
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

| File | Suites (filter the source identifier, not the `@Suite` title) |
| --- | --- |
| `ActionTests.swift` | Actions |
| `ActionIdentityTests.swift` | Action identity — filter `ActionIdentityTests` |
| `AdaptiveSurfaceTests.swift` | Adaptive terminal surface |
| `AccessibilitySnapshotTests.swift` | Accessibility snapshot |
| `AppleHostAccessibilityTests.swift` | AppKit accessibility bridge |
| `AppleHostFontCacheTests.swift` | AppKit host styled-font cache |
| `AppleHostNativeRegionTests.swift` | AppKit host native regions |
| `AppleHostPointerTests.swift` | AppKit host pointer translation: real NSEvents, the long-press timer, the scroll sign (ADR 0018) |
| `AppleHostTests.swift` | AppKit host |
| `AppleNativeHostTests.swift` | AppKit layout metrics, AppKit native host, AppKit native host regions — filter `AppKitLayoutMetricsTests`, `AppleNativeHostTests`, `AppleNativeHostRegionTests` |
| `AppleShellTests.swift` | AppKit scene shell |
| `CellSerializerTests.swift` | Cell serializer |
| `CompletionStatusTests.swift` | Completion status |
| `ControlDescriptorTests.swift` | ControlDescriptor build, host table, sizing; control registration; host activation and focus — filter `ControlDescriptorBuildTests`, `ControlDescriptorHostTests`, `ControlDescriptorSizingTests`, `ControlRegistrationTests`, `HostActivationTests` |
| `DrawListTests.swift` | Cell buffer, DrawList, Cell painter |
| `EmbedABITests.swift` | Embed ABI additions; embed pointer ABI (ADR 0018) — filter `EmbedABITests`, `EmbedPointerABITests` |
| `EmbedTests.swift` | C embedding context |
| `FailureExitCodeTests.swift` | Validated failure exit codes — filter `--filter FailureExitCodeTests` |
| `FormControlTests.swift` | Form controls and identity |
| `FrameHostTests.swift` | FrameHost |
| `GamepadInputTests.swift` | Gamepad input — filter `GamepadInputTests` |
| `GeometryTests.swift` | Geometry |
| `HostPumpTests.swift` | Host pump |
| `LayoutMetricsTests.swift` | LayoutMetrics parity with `.cell`, scaling; FrameHost metrics — filter `LayoutMetricsParityTests`, `LayoutMetricsScalingTests`, `FrameHostMetricsTests` |
| `LayoutTests.swift` | Layout |
| `MacroExpansionTests.swift` | Macro expansion |
| `MacroUsageTests.swift` | Macro public surface; reactive state lifetime |
| `MLIRFixtureTests.swift` | MLIR fixtures |
| `MLIRTests.swift` | MLIR |
| `ModernTests.swift` | DrawList codec; overflow-safe geometry; CellPainter ↔ DrawList |
| `NativePresentationTests.swift` | Presentation tree, diff, and from a host — filter `PresentationTreeTests`, `PresentationDiffTests`, `PresentationHostTests` |
| `NativeRegionTests.swift` | Native region build, host table — filter `NativeRegionBuildTests`, `NativeRegionHostTests` |
| `P1LayoutTests.swift` | Border title, divider axis, TextField C0, emoji presentation, button focus |
| `PointerBackendTests.swift` | Backend pointer translation (ADR 0018): the C/WASM wire codes, terminal SGR decoding, Windows console mouse, the cross-backend scroll sign, backend idioms — filter `PointerWireTests`, `SGRMouseTests`, `WindowsMouseTranslatorTests`, `ScrollConventionTests`, `BackendIdiomTests` |
| `PointerGestureTests.swift` | Pointer event and idiom policy; host-owned gesture recognition (ADR 0018) — filter `PointerPolicyTests`, `PointerGestureTests` |
| `PluginCommandTests.swift` | Plugin commands |
| `PluginRuntimeTests.swift` | Plugin runtime: manifest, grants, lifecycle |
| `PluginSceneTests.swift` | Plugin scene contributions |
| `PluginSlotTests.swift` | Plugin slots |
| `PlatformServicesTests.swift` | Platform services: scoped filesystem, clock, log |
| `POSIXTerminalIntegrationTests.swift` | PTY raw-mode restore; byte-wise escape, UTF-8 and SGR mouse decoding (Darwin) |
| `ProgressViewTests.swift` | ProgressView scale awareness |
| `RunIterationTests.swift` | Run iteration |
| `RuntimeLoopTests.swift` | Runtime loop |
| `SceneTests.swift` | Scene graph; window actions; lifecycle — filter `SceneGraphTests` |
| `SignalTests.swift` | Signal |
| `StreamOutputTests.swift` | Author-declared stream output |
| `StreamPresenterTests.swift` | Stream presenter |
| `StyleTests.swift` | Style |
| `TerminalCapabilityTests.swift` | Terminal capabilities and cell diff — filter `TerminalCapabilityTests` |
| `TerminalRescueTests.swift` | Terminal process-global rescue |
| `TestSupport.swift` | No suite; shared helpers, including `TestBox` |
| `TextFieldCursorTests.swift` | TextEditing pure functions; TextField cursor and selection — filter `TextFieldCursorTests` |
| `VirtualizedListTests.swift` | Virtualized list — filter `VirtualizedListTests` |
| `ViewBuilderTests.swift` | View builder (including ZStack overlay vs group); filter `--filter ViewBuilderTests` |
| `ViewStateIdentityTests.swift` | View-state identity |
| `WASMSerializerTests.swift` | WASM HTML serializer (compiled off wasm32) |
| `WebDemoStateTests.swift` | Web demo state |
| `WindowsTerminalTests.swift` | Native Windows console key translation (runs on every host) |

## Conventions

- `@Suite("…")` + `@Test("…")`. Prefer `#expect` over `Issue.record` except
  when a `guard case` must exit early.
- Observer counters use `TestBox`, an `@unchecked Sendable` box in
  `TestSupport.swift`. It became target-internal when the catch-all split, so
  it is no longer file-local. Do not add
  `nonisolated(unsafe)` in GamaCore; tests may, but the box is the default.
- Macro expansion tests call `assertMacroExpansion` from
  `SwiftSyntaxMacrosGenericTestSupport` with a `failureHandler` that records
  a Swift Testing `Issue`. Do not reintroduce `SwiftSyntaxMacrosTestSupport`
  (it imports XCTest).
- Platform suites stay behind `#if canImport(AppKit)` or
  `#if canImport(Darwin)`. Pure translators that need no platform API (the
  Windows console key and mouse translators, the SGR decoder) are compiled
  everywhere and tested on every host instead.
- New tests go in Swift Testing. There is no XCTest fallback.

## Linux sanitizers

Linux sanitizer proof separates two contracts which cannot honestly share a
process. The GitHub-hosted Linux job that ran both was removed on 2026-09-28,
so today they run only on a Linux host by hand:

- `swift test --sanitize address` retains broad address-safety coverage, with
  `detect_leaks=0` only because SwiftPM's generated runner loads an XCTest
  harness that retains process-lifetime suite metadata.
- `scripts/check-linux-leaks.sh` builds `gama-leak-check` with ASan and runs
  the executable directly under `detect_leaks=1`. The clean path constructs,
  pumps, and destroys a real `FrameHost` without Swift Testing or XCTest. The
  same binary's `--deliberate-leak` path intentionally retains a GamaCore
  `Signal`; the gate requires LeakSanitizer's exact configured failure code and
  diagnostic before the gate can pass. No suppression file is involved.

LeakSanitizer leak detection is unsupported on Darwin. macOS can prove that
the executable builds and its clean lifecycle runs, but only a Linux host can
prove both the clean LSan result and the failing negative control.
