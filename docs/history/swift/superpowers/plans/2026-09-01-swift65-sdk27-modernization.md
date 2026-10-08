# Swift 6.5-dev and SDK 27 Modernization Implementation Plan

**Status:** Implemented and locally verified on 2026-09-02. Exact-commit
hosted proof is reported by the acceptance workflow; external skill changes
remain outside this repository.

> **For agentic workers:** Execute each task in order in the assigned
> worktree. Keep commits focused, preserve external skill ownership, and use
> repository-selected toolchains and scratch paths.

**Goal:** Modernize the seven requested Swift/SwiftUI skills and adopt the
small set of compiler-proven Swift 6.4/6.5 features that strengthen Gama's
cross-platform macro/plugin and confinement contracts.

**Architecture:** Gama remains a stdlib-only retained core feeding one shared
draw pipeline. `GamaMacrosImpl` stays a host compiler plugin and gains
defensive module selectors; host-confined types gain explicit `~Sendable`
alongside their existing unavailable-conformance diagnostic. Backend work is
limited to executable evidence and honest documentation.

**Spec:**
`docs/superpowers/specs/2026-09-01-swift65-sdk27-modernization-design.md`

## Global constraints

- Run `unset TOOLCHAINS` before Swift commands. Gama commands use
  `swiftly run swift`; Xcode SDK probes use `/usr/bin/xcrun --toolchain default`.
- Keep `Package.swift` at `swift-tools-version: 6.4`, preserve
  `Package.resolved` and every pin in `Toolchains.toml`, and use scratch paths
  outside the FileProvider checkout.
- `GamaCore` and `GamaPlugin` remain stdlib-only. Do not add runtime package
  dependencies or move host state into process-global registries.
- Keep the published `gama_embed_v1_*` and `gama_web_v1_*`/`v2_*` exports on
  `@_cdecl`; direct `@c` migration is forbidden because it changes emitted
  symbols and ABI.
- `Signal` and `PluginRuntime` must spell `~Sendable` on the declaration and
  retain the unavailable `@unchecked Sendable` extension that produces
  `#UnavailableSendableConformance` for retroactive unchecked conformances.
- Macro expansions use `GamaCore::` module selectors without changing macro
  roles, public declarations, or the SwiftSyntax revision.
- Gama remains independent of SwiftUI. SDK 27 SwiftUI findings update skills
  and the audit document, not Gama's renderer or deployment targets.
- Edit the central `swift` skill only at `/Users/donaldfilimon/.grok/skills/swift`,
  then use the central sync and verify all mirrors. The six curated plugin
  skill directories are active cache copies and may be replaced by upgrades;
  disclose that durability limit.
- Do not edit the generic Superpowers orchestration skills with Swift-specific
  material. They are process inputs for this run, not Swift API targets.
- Tests use Swift Testing only. Do not weaken or skip any repository gate.

## Task 1: Modernize the requested Swift and SwiftUI skills

**Owned paths:**

- `/Users/donaldfilimon/.grok/skills/swift/`
- `/Users/donaldfilimon/.codex/plugins/cache/openai-curated-remote/build-macos-apps/0.1.4/skills/swiftpm-macos/`
- `/Users/donaldfilimon/.codex/plugins/cache/openai-curated-remote/build-macos-apps/0.1.4/skills/swiftui-patterns/`
- `/Users/donaldfilimon/.codex/plugins/cache/openai-curated-remote/build-ios-apps/0.1.2/skills/swiftui-liquid-glass/`
- `/Users/donaldfilimon/.codex/plugins/cache/openai-curated-remote/build-ios-apps/0.1.2/skills/swiftui-performance-audit/`
- `/Users/donaldfilimon/.codex/plugins/cache/openai-curated-remote/build-ios-apps/0.1.2/skills/swiftui-ui-patterns/`
- `/Users/donaldfilimon/.codex/plugins/cache/openai-curated-remote/build-ios-apps/0.1.2/skills/swiftui-view-refactor/`
- Add `docs/Swift65SDK27.md`; modify `docs/README.md`.

Update each entrypoint and only its routed references. Apply the corrections
listed in the spec, including exact platform availability from installed SDK
interfaces, `@Bindable` and `@State` macro rules, actor-context cautions,
stable identity/environment guidance, semantic accessibility, and trace-backed
performance. Remove absent API examples and arbitrary numeric/global
architecture rules. Keep the central skill repository-specific and add only
the exact snapshot/Xcode split plus probe-before-adoption rule.

Write `docs/Swift65SDK27.md` as the durable audit: toolchain facts, adopted
features, deliberate non-adoptions, SDK 27 corrections, and evidence layers.
Link primary official sources and distinguish local compiler/API proof from
runtime, hosted, and manual acceptance.

Run the `skill-creator` validator on all seven packages. Run the central sync
driver and its ABI mirror launcher, then require identical tree hashes for the
three central `swift` copies. Type-check representative Swift 6.5 and macOS 27
snippets from the updated guidance.

Commit the tracked audit/index changes as:

```text
docs: record Swift 6.5 and SDK 27 modernization
```

The external skill edits are intentionally outside Git; record their paths,
validation output, and final hashes in the task report.

## Task 2: Modernize confinement and macro-generated names

**Files:**

- `Sources/GamaCore/State.swift`
- `Sources/GamaPlugin/PluginRuntime.swift`
- `Sources/GamaMacrosImpl/Plugin.swift`
- `Tests/gamaTests/MacroExpansionTests.swift`
- `Tests/Fixtures/Confinement/warn.SendableConformanceIsFlagged.swift`
- `scripts/check-boundaries.sh`
- `docs/adr/0009-signal-is-not-sendable.md`

Add `~Sendable` to the two host-confined declarations and preserve the
unavailable extensions. Update comments and ADR wording to describe the
combined contract. Add a boundary assertion that both spellings remain, while
retaining the existing external retroactive-conformance warning fixture.

Change every GamaCore reference emitted by the compiler plugin to a defensive
module selector and update exact expansion expectations. Add or adjust tests
so `@Component`, `@Reactive`, and `#rgb` all prove the new spelling and still
compile in real macro use.

Focused verification:

```bash
unset TOOLCHAINS
swiftly run swift test --scratch-path /private/tmp/gama-framework-swiftpm --filter Macro
./scripts/check-boundaries.sh
./scripts/check-concurrency-negative.sh
```

Commit as:

```text
refactor: adopt explicit confinement and module selectors
```

## Task 3: Turn backend assumptions into executable evidence

**Files:**

- `scripts/check-wasm.sh`
- `docs/backends/WASM.md`
- `docs/backends/Android.md`
- `docs/Swift65SDK27.md` only if verification changes an evidence statement.

Add a fail-closed source policy to the Wasm gate: exactly one declaration in
`Sources/GamaWASM` may use `nonisolated(unsafe)`, and it must be the private
installed-host slot. Document initial no-host status, install/reinstall
replacement behavior, single-threaded reactor ownership, and the requirement
for a new isolation/ABI design before threaded or multi-host Wasm.

Replace Android's blanket broken-pipe rerun instruction with the current
capability-ledger distinction and point maintainers at the readiness/emulator
gate. Do not claim a runtime execution that this task did not perform.

Verification:

```bash
./scripts/check-wasm.sh
./scripts/check-docs.sh
./scripts/check-doc-coverage.sh
./scripts/check-apple.sh
./scripts/check.sh
```

The full driver may expose missing SDK/NDK/emulator/MLIR prerequisites. Record
the exact first failing gate and retain fail-closed behavior; do not translate
partial local evidence into hosted or manual acceptance.

Commit as:

```text
test: enforce backend isolation evidence
```

## Expected final contract

- Seven requested Swift/SwiftUI skills updated and validated; generic
  Superpowers skills unchanged.
- Gama macro expansions use `GamaCore::` selectors and remain host-build-only.
- `Signal` and `PluginRuntime` express intentional non-Sendability with both
  the modern opt-out and the existing attributable warning contract.
- Published C/Wasm symbols and package/deployment/toolchain pins are unchanged.
- The single Wasm unsafe global is mechanically allowlisted, and the Android
  guide no longer dismisses real failures as infrastructure.
- Local verification results are recorded without upgrading them to hosted,
  live, simulator, accessibility, or packaging proof.
