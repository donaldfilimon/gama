# Swift 6.5-dev and SDK 27 audit

Status: **Draft evidence report. Local source/interface inspection and
standalone compiler probes were completed on 2026-09-01; the Gama adoptions
described below are accepted plan direction but are not implemented on
`main`.** This document records the bounded modernization decision and its
evidence limits. It does not by itself establish a Gama build, runtime,
manual UI, packaging, hosted-CI result, or current external-skill state.

## Why this audit exists

Gama intentionally combines a main-development compiler with a manifest and
Apple platform gates that must remain consumable by Xcode's integrated SwiftPM.
New syntax is adopted only when it solves an existing problem and passes every
affected supported route. The framework remains a retained, cross-platform UI
core: this work does not add SwiftUI to Gama or change its renderer.

The accompanying plan also proposes corrections to requested Swift/SwiftUI
skills against the installed compiler and public SDK interfaces. Those skills
live outside this repository, so their current contents and validation must be
checked where they are installed. Plugin-cache copies are not durable upstream
packages and a future plugin update can replace them.

## Exact local toolchain and target facts

Observed from the Gama worktree with `TOOLCHAINS` unset:

| Layer | Observed value |
| --- | --- |
| Gama selector | `main-snapshot-2026-08-21` from `.swift-version` |
| Pinned compiler | Apple Swift 6.5-dev; Swift `95c5142e84b82c1`; LLVM `64c3046d94ae7cc`; `+assertions` |
| Pinned compiler tag | `swift-DEVELOPMENT-SNAPSHOT-2026-08-21-a` |
| Pinned target | `arm64-apple-macosx27.0.0`; runtime compatibility 6.4 |
| Xcode | 27.0, build `27A5252f` |
| Installed Xcode compiler | Apple Swift 6.4, `swiftlang-6.4.0.33.1`, Clang `2100.3.33.1` |
| Xcode target | `arm64-apple-macosx27.0.0`; runtime compatibility 6.4 |
| Installed macOS SDK | 27.0 at Xcode's `MacOSX.sdk` |
| Package manifest | `swift-tools-version: 6.4`, Swift language mode 6 |
| Declared Apple deployment targets | macOS 14, iOS 17, tvOS 17, visionOS 1 |
| Windows exception | Swift 6.4.x snapshot selected in `Toolchains.toml`; Windows is not 6.5-dev-proven |

`Toolchains.toml` remains the repository pin and artifact authority. Its
compiler/SDK URLs, revisions, checksums, SwiftSyntax revision, deployment
targets, products, and CI policy are unchanged by this modernization.

## Sources and method

Language status is taken from implemented Swift Evolution proposals, the exact
snapshot compiler source/interface, and local probes:

- [SE-0491: Module selectors for name disambiguation](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0491-module-selectors.md)
- [SE-0518: `~Sendable` for explicitly non-Sendable types](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0518-tilde-sendable.md)
- [SE-0522: Source-level control over compiler warnings](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0522-source-warning-control.md)
- [SE-0495: C-compatible functions and enums](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0495-cdecl.md)
- [Swift Evolution process: Accepted is not the same as Implemented](https://github.com/swiftlang/swift-evolution/blob/main/process.md)

Apple API and practice decisions use the installed macOS 27
`.swiftinterface` files plus official Apple material:

- [What's new in SwiftUI (WWDC26)](https://developer.apple.com/videos/play/wwdc2026/269/)
- [Use SwiftUI with AppKit and UIKit (WWDC26)](https://developer.apple.com/videos/play/wwdc2026/272/)
- [Improve app responsiveness with Instruments (WWDC26)](https://developer.apple.com/videos/play/wwdc2026/268/)
- [Explore concurrency in SwiftUI (WWDC25)](https://developer.apple.com/videos/play/wwdc2025/266/)
- [Optimize SwiftUI performance with Instruments (WWDC25)](https://developer.apple.com/videos/play/wwdc2025/306/)
- [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views?changes=latest_major)
- [SwiftUI `Bindable`](https://developer.apple.com/documentation/swiftui/bindable)
- [SwiftUI accessibility fundamentals](https://developer.apple.com/documentation/swiftui/accessibility-fundamentals)

When prose, an exported availability table, and the installed public interface
conflict, a minimal compiler probe against the product's selected SDK controls
code examples. A successful probe still proves only that compiler/SDK/target
combination.

## Standalone compiler probe results

The same representative sources were type-checked with:

```bash
unset TOOLCHAINS
swiftly run swiftc -typecheck -swift-version 6 <probe.swift>
/usr/bin/xcrun --toolchain default swiftc -typecheck -swift-version 6 <probe.swift>
```

| Probe | Swift 6.5-dev pin | Xcode Swift 6.4 | Meaning |
| --- | --- | --- | --- |
| `Swift::Int` module selector | pass | pass | Cross-gate language baseline |
| `struct Token: ~Sendable` | pass | pass | Cross-gate language baseline |
| `@diagnose(DeprecatedDeclaration, as: warning, reason: ...)` | pass; expected warning retained | pass; expected warning retained | Scoped diagnostic control is available |
| `#if os(anyAppleOS)` | pass | pass | Available, but only appropriate for truly all-Apple-OS code |
| `@c(name)` with an `Int32` signature | pass | pass | Syntax/type proof only; not ABI migration proof |
| Observation owner using explicit `State(initialValue:)` plus injected `@Bindable` | pass | pass | Representative Xcode 27 state/binding pattern |
| macOS `.toolbarMinimizeBehavior(.automatic, for: .windowToolbar)` | **fail:** `View` has no member | **fail:** `View` has no member | Do not advertise this spelling as a macOS API |
| macOS `.toolbarMinimizationBehavior(.automatic, for: .windowToolbar)` | pass | pass | This is the spelling present in the installed public interface |

The toolbar result is deliberately exact. An Xcode-exported table described
`toolbarMinimizeBehavior`, but the installed macOS 27 public interface and
both compilers reject that spelling. The interface instead exposes
`toolbarMinimizationBehavior(_:for:)`. Re-probe a later SDK before changing
examples.

## Planned, not-yet-implemented Gama adoption

### Accepted direction; implementation pending

- Macro-generated references would use defensive module selectors:
  `GamaCore::View`, `GamaCore::Signal`, and `GamaCore::Color`. This
  prevents a client declaration named `GamaCore` from changing lookup.
  Macro roles, arguments, products, and the pinned build-time-only SwiftSyntax
  dependency remain unchanged.
- `Signal` and `PluginRuntime` would explicitly declare `~Sendable`. Their
  existing unavailable `@unchecked Sendable` extensions remain: the tilde
  spelling documents/prevents implicit Sendability, while the unavailable
  conformance preserves Gama's actionable diagnostic contract.

These are plan decisions, not current-source claims. Exact macro
expansion/real-use tests plus the boundary and concurrency-negative gates are
required acceptance proof when implemented; this document does not replace
those results.

### Documented but deliberately not adopted

- **`@c`:** Gama's published C, Android, and Wasm exports remain
  `@_cdecl`. SE-0495 and object-symbol inspection show that `@_cdecl`
  emits a named C symbol and a Swift-convention symbol, while `@c` emits only
  the C symbol. Conversion therefore requires a separately versioned ABI,
  rebuilt-consumer policy, symbol manifest, and every target gate.
- **`anyAppleOS`:** useful only when code genuinely applies to every Apple
  OS. Gama's `canImport(AppKit)`/`canImport(UIKit)` checks express framework
  capability more precisely and are not rewritten for style.
- **`@diagnose`:** reserved for a narrow named diagnostic around an
  unavoidable compatibility bridge, with a reason and removal condition.
  There is no current Gama use that justifies suppressing or downgrading a
  boundary, portability, ownership, or concurrency diagnostic.
- **Other main-development features:** syntax or an Accepted proposal is not a
  requirement. Post-6.4, experimental, availability-`9999`, or future-only
  features stay out until they solve a supported requirement and pass the
  full affected matrix.
- **SwiftUI APIs:** Gama does not adopt SwiftUI. Planned SwiftUI modernization
  applies to the requested local skills, not the framework product graph.

## SwiftUI and macOS 27 corrections recorded

- Ownership comes before wrapper choice. Read an injected `@Observable`
  directly; use stored or local `@Bindable` only when bindings to its
  properties are required.
- Xcode 27 `@State` initialization uses one source. If `init` supplies a
  value, remove the declaration default and use an explicit initializer.
  `_model = State(initialValue: ...)` remains compiler-accepted. Do not rely
  on private memberwise synthesis or composed wrappers with colliding backing
  storage.
- SwiftUI view actions and `.task` inherit actor context. `Task {}` is not
  an off-main guarantee; CPU-heavy work needs an explicit actor,
  `@concurrent`, or other Sendable non-main boundary, followed by UI mutation
  on `MainActor`.
- Stable, unique domain identity is required for mutable/reorderable
  collections. Nested observable references are supported, but one observed
  collection property is still a coarse dependency. Environment instances
  and defaults must be stable, especially for high-frequency values.
- Tabs, navigation stacks, and centralized sheets are conditional product
  architectures, not universal scaffolding. Use tabs for peer destinations,
  navigation for hierarchy, local `sheet(item:)` for selected items,
  `sheet(isPresented:)` for flags, and route-level presentation only when
  distant features truly share ownership.
- `Window` is a supported unique macOS main/utility scene; `WindowGroup`
  represents independently instantiable scenes. A particular activation
  failure must be reproduced in that app rather than encoded as a SwiftUI rule.
- Liquid Glass custom-view APIs in this SDK are available on iOS, macOS, tvOS,
  and watchOS 26+ and unavailable on visionOS. macOS 27 improves pointer
  interaction but does not change the macOS 26 introduction. Standard controls
  adapt automatically; custom glass belongs sparingly in the control layer,
  not on ordinary content cards. The installed `glassEffect(_:in:)`
  signature has no `isEnabled:` parameter, and no public
  `scrollExtensionMode` declaration was found.
- Prefer semantic controls. Accessibility identifiers are for automation, not
  spoken names. Custom UI must preserve role, name, value/state, actions,
  focus/keyboard operation, and alternatives to hover/gesture/color, then be
  exercised with assistive technologies and relevant motion,
  transparency/contrast, and Show Borders settings.
- Code review generates performance hypotheses. Runtime diagnosis requires an
  optimized-build Instruments or comparable capture that distinguishes body
  invalidation, identity churn, layout, rendering/image/animation,
  actor/executor, and data-layer work, followed by the same capture after the
  smallest fix.

## Evidence layers and claim boundary

| Layer | What this audit can record | What it does not prove |
| --- | --- | --- |
| Source/interface inspection | Exact declarations, availability annotations, package pins, generated source, and policy guards | Compilation, runtime behavior, or another SDK |
| Compiler/type-check probes | One spelling and representative use compile or fail under the named compiler/SDK/target | Ownership errors that emerge only in SIL, ABI/symbol preservation, runtime behavior, or other targets |
| Local Gama build/tests | The named local gate passed at the tested commit and environment | Hosted runners, browser/device interaction, packaging, accessibility, or manual UI |
| Runtime/manual acceptance | The exact app/device/browser/accessibility interaction was exercised | A different OS, device, configuration, or hosted runner |
| Hosted CI | The exact pushed commit passed the named required job | Unrun manual acceptance or a later local/unpushed state |

For noncopyable negative probes, use `swiftc -c`, not only
`swiftc -typecheck`, because ownership enforcement can occur after type
checking. For Gama acceptance, keep `TOOLCHAINS` unset, use the pinned
`swiftly` route and outside-FileProvider scratch paths, and let missing SDK,
emulator, browser, MLIR, or hosted evidence fail closed. Never convert a
missing prerequisite into a passed platform claim.
