# Swift 6.5-dev and SDK 27 modernization

Status: Accepted for implementation on 2026-09-01. This design is a bounded
modernization of Gama and the explicitly requested local Swift/SwiftUI skills;
it is not a framework rewrite.

## Problem

The machine now combines a pinned Swift 6.5-dev main snapshot with Xcode 27,
Apple Swift 6.4, and the macOS 27 SDK. The installed skills predate several
language and SwiftUI changes, contain a few platform mistakes, and sometimes
turn performance heuristics into universal rules. Gama is already a
cross-platform retained UI framework with a host-only compiler plugin, but it
does not yet use module selectors in generated code or Swift's explicit
`~Sendable` audit spelling. Its Android guide also contradicts the capability
ledger, and its one Wasm `nonisolated(unsafe)` global is documented but not
source-gated.

## Evidence baseline

- The pinned compiler reports Swift 6.5-dev, revision
  `95c5142e84b82c1`, targeting macOS 27.
- Xcode 27 build `27A5252f` provides Apple Swift 6.4 and the macOS 27 SDK.
- Local compiler probes accept `@c`, `~Sendable`, `anyAppleOS`, `@diagnose`,
  and `Module::Declaration` selectors.
- Symbol inspection proves that `@_cdecl` emits both a C and Swift symbol,
  while `@c` emits only the C symbol. SE-0495 therefore makes a direct
  conversion of Gama's published exports an ABI break.
- The installed macOS SDK accepts interactive Liquid Glass,
  `EnvironmentValues.appearsActive`, toolbar visibility priority, and toolbar
  content-margin removal. It rejects `toolbarMinimizeBehavior` on macOS in
  this seed, despite a conflicting Xcode-exported availability table; the
  compiler and public interface are authoritative for code examples.
- The pre-change Apple gate passes its debug build and all 253 Swift Testing
  cases; release validation is recorded by the implementation ledger.

Primary sources are Apple's WWDC26 Swift and SwiftUI sessions, installed SDK
interfaces, Xcode 27's exported SwiftUI guidance, and implemented Swift
Evolution proposals. Research is summarized in `docs/Swift65SDK27.md`.

## Design

### Skill packages

Update only the requested Swift/SwiftUI skills. Keep the generic Superpowers
orchestration skills unchanged: they govern task decomposition and review, not
Swift APIs.

The central `swift` skill remains a machine/repository router. Its toolchain
reference gains the exact Gama snapshot split and a rule to verify main-only
features with the selected compiler. After editing the central source, run the
existing central sync and verify its `.grok`, `.codex`, and `.agents` mirrors
are byte-identical.

The six plugin-provided skills are installed cache copies. Update them in
place because they are the active requested skills, validate each package, and
record that a future plugin refresh can replace those edits. Keep entrypoints
short and move SDK matrices or conditional detail to compact references.

Required corrections include:

- repository-selected toolchains and scratch paths before generic SwiftPM;
- intent-based macOS scene/file organization with no implicit Git/bootstrap
  side effects;
- cross-platform Liquid Glass availability, semantic-control-first design,
  accessibility settings, and removal of absent APIs;
- trace-backed performance conclusions and modern Instruments routing;
- `@Bindable`, actor inheritance, stable identity/environment values, and
  conditional rather than universal navigation/presentation patterns;
- Xcode 27 `@State` macro initialization rules and evidence-based view
  extraction.

### Gama language and macro adoption

Add `~Sendable` directly to `Signal` and `PluginRuntime`, while retaining their
unavailable `@unchecked Sendable` extensions. The combination communicates the
modern explicit opt-out and preserves Gama's existing named diagnostic for a
consumer's retroactive unchecked conformance. It has no runtime or ABI
representation.

Use defensive module selectors in compiler-generated declarations:
`GamaCore::View`, `GamaCore::Signal`, and `GamaCore::Color`. Update byte-exact
macro expansion tests. Do not change the public macro roles, shipped products,
SwiftSyntax revision, or runtime dependency graph.

### Backend evidence

Keep `@_cdecl` on every published C and Wasm symbol. New exports may consider
`@c` only under a separately versioned ABI and consumer audit.

Make the Wasm reactor assumption executable: the Wasm gate must reject any
`nonisolated(unsafe)` declaration in `GamaWASM` except the single private
installed-host slot. Document install/reinstall semantics and state that
threaded Wasm requires a new isolated lifecycle design.

Correct the Android guide so installation failure is a gate/product failure
unless a specific readiness diagnostic proves an external transport failure.
Do not restore the retracted blanket infrastructure-flake claim.

## Non-goals

- No SwiftUI dependency or migration of Gama's retained renderer.
- No deployment-target, `swift-tools-version`, SwiftSyntax pin, package
  product, C symbol, CI workflow, or hosted-evidence claim change.
- No speculative adoption of post-6.4 proposals merely because the main
  snapshot parses them.
- No state-lifetime redesign, UIKit runtime harness, filesystem confinement
  change, or unmeasured rendering optimization in this slice.

## Acceptance

- Every requested skill validates; the central `swift` mirrors match.
- Macro expansion and public macro usage tests pass with module selectors.
- Boundary and concurrency-negative gates prove the combined `~Sendable` and
  unavailable-conformance contract.
- The Wasm policy guard and runtime/browser smoke pass where the pinned SDK is
  available.
- Documentation and coverage gates pass.
- The Apple gate and the complete local acceptance driver are run without
  weakening; missing external prerequisites remain failures or explicitly
  unproven evidence, never inferred success.
