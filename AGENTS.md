# Gama Framework agent guide

Gama is a Swift 6.4 SwiftPM framework. The default package contains a portable
retained UI core, macros, shared drawing, terminal, Apple, WASM, C embedding,
MLIR, and demo targets. `Adapters/GamaQt` is an isolated optional package.

## Gates

- Apple debug/test/release: `./scripts/check-apple.sh`
- Portable ownership/import rules: `./scripts/check-boundaries.sh`
- Exact Swift 6.4 Embedded proof: `./scripts/check-embedded.sh`
- Android cross-build and JNI packaging: `ANDROID_NDK_HOME=… ./scripts/check-android.sh`
- Full acceptance, including required runtime blockers: `./scripts/check.sh`

Always unset `TOOLCHAINS` for Xcode Swift 6.4 work. Do not use PATH `swift`,
which is Swiftly-managed. Do not weaken or skip a required cross-platform gate
to make the matrix green.

## Architecture rules

- `GamaCore` stays stdlib-only and owns no global mutable registries.
- Views compile to `RenderNode`; layout and paint semantics are shared by all
  backends.
- Each `FrameHost` owns focus, actions, subscriptions, dirty state, and frames.
- Platform targets translate events and present `DrawList`; they do not fork
  application semantics.
- C and WASM symbols remain versioned and separately namespaced.
- Qt remains optional and does not enter the root dependency graph.
- Documentation must distinguish implemented, locally proven, hosted proven,
  provisional, and blocked states.

Prefer small reviewable commits, preserve `Package.resolved`, never commit
credentials or runner configuration, never force-push the default branch, and
only merge after required checks are green.
