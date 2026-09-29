# Android backend (JNI over GamaEmbed)

Status: Unverified. Capability status lives in
[`Capabilities.md`](../Capabilities.md); this guide does not restate
hosted or local proof. The demo declares
its inline tap counter with `@Component` and `@Reactive` (ADR 0011).

An APK installation, readiness, or input/frame failure is a product/gate
failure by default; rerunning it is not acceptance evidence. Classify a
failure as external transport only when the readiness or emulator diagnostics
identify a concrete fault such as an unavailable adb shell transport. Slow
package-manager readiness is not itself a dropped transport. The bounded
recovery and stage-exhaustion behavior is exercised by
`scripts/test-android-emulator-readiness.sh`; a persistent failure after those
diagnostics remains a failed gate.

## How it fits together

Android consumes the same flat C ABI as every other foreign host: the
sample dynamic library `GamaAndroidDemo` bootstraps an app and returns a
`GamaEmbed` context (`Examples/Android/AndroidDemoBootstrap.swift`,
`@_cdecl("gama_android_demo_v1_create")`); the returned pointer's lifetime
belongs to the `gama_embed_v1_*` family (`destroy` releases it).

`Examples/Android/` is a complete Gradle project:

- `app/src/main/cpp/gama_jni.cpp` + `CMakeLists.txt` — the thin JNI shim
  bridging Kotlin to the C entry points (contexts travel as `jlong`).
- `app/src/main/java/com/gama/example/GamaNative.kt` — the JNI surface.
- `DrawListDecoder.kt` — a Kotlin reader of the DrawList wire format that
  renders frames to Android views.
- `MainActivity.kt` — drives resize/key/pointer into the context. The grid
  font is 14 sp (`TypedValue.COMPLEX_UNIT_SP`), designed so it follows
  screen density and the system font scale. The view measures its cell from
  that font and resizes the grid to the whole cells that fit on layout and on
  a configuration change; the manifest declares `fontScale` and `density` in
  `configChanges` so that the change is meant to reach the view instead of
  recreating the activity. `check-android.sh` checks only that this builds;
  no runtime test exercises a density or font-scale change. The acceptance probe still runs against a fixed 40x12 grid
  before the first layout.

## Building

`ANDROID_NDK_HOME=… ./scripts/check-android.sh` cross-compiles GamaEmbed
and the demo library for both ABIs with the pinned SDK (ids/SHA-256 in
`Toolchains.toml`) and the pinned NDK 30.0.15729638, then packages
`jniLibs` — including the transitive `.so` closure and `libc++_shared.so`,
which the Swift runtime requires at load time.
`scripts/check-android-emulator.sh` is the runtime proof. CI ran it on a
GitHub-hosted Ubuntu emulator until that job was removed on 2026-09-28; it is
now a local gate only. It first exercises the fail-closed readiness policy, and
then requires the input-driven frame assertion. See
[`../Capabilities.md`](../Capabilities.md) for the current evidence boundary.
