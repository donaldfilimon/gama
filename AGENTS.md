# Gama Framework agent guide

Gama is a SwiftPM framework built with the pinned Swift 6.5-dev main snapshot (`.swift-version`: `main-snapshot-2026-08-21`, toolchain id `org.swift.65202608211a`). The default package contains a portable
retained UI core, macros, shared drawing, terminal, Apple, WASM, C embedding,
MLIR, and demo targets.

## Gates

- Apple debug/test/release: `./scripts/check-apple.sh`
- Portable ownership/import rules: `./scripts/check-boundaries.sh`
- Exact pinned-snapshot Embedded proof: `./scripts/check-embedded.sh`
- Android cross-build and JNI packaging: `ANDROID_NDK_HOME=… ./scripts/check-android.sh`
- Full acceptance, including required runtime blockers: `./scripts/check.sh`

Always unset `TOOLCHAINS` first; the check scripts pin the snapshot toolchain
explicitly via `xcrun --toolchain org.swift.65202608211a`. This repository is
the machine-wide exception to the "Xcode default toolchain" rule. Do not weaken
or skip a required cross-platform gate to make the matrix green.

**Run the codebase through swiftly.** For ad-hoc builds, runs, and tests use
`swiftly run swift <build|run|test|…>` from the repo root: swiftly reads
`.swift-version` and selects the pinned `main-snapshot-2026-08-21` toolchain
automatically, so it is equivalent to the scripts' explicit `xcrun
--toolchain` pin without hardcoding the toolchain id.

```bash
unset TOOLCHAINS
swiftly run swift build
swiftly run swift run gama-demo
swiftly run swift test --scratch-path /private/tmp/gama-framework-swiftpm
```

`swift test` still needs the `--scratch-path` outside iCloud (see below).
Verify identity with `swiftly run swift --version` (must report 6.5-dev).

This checkout lives under iCloud-managed `~/Desktop`: run `swift test` only
through the check scripts or with `--scratch-path` outside iCloud, and never
run `git gc`, `git prune`, `git fsck`, or `git repack` here.

## Architecture rules

- `GamaCore` stays stdlib-only and owns no global mutable registries.
- Views compile to `RenderNode`; layout and paint semantics are shared by all
  backends.
- Each `FrameHost` owns focus, actions, subscriptions, dirty state, and frames.
- Platform targets translate events and present `DrawList`; they do not fork
  application semantics.
- C and WASM symbols remain versioned and separately namespaced.
- Documentation must distinguish implemented, locally proven, hosted proven,
  provisional, and blocked states.

Prefer small reviewable commits, preserve `Package.resolved`, never commit
credentials or runner configuration, never force-push the default branch, and
only merge after required checks are green.
