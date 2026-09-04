# Android backend (JNI over GamaEmbed)

Status: Locally runtime proven with the pinned Android Swift SDK
(arm64-v8a/x86_64 payloads) and hosted proven by the required API 36
emulator input/frame round trip (`Tapped 0` → `Tapped 1`). The demo builds
its tap counter inline in the scene closure on a `ReactiveSlot` (the code
`@Component` would synthesize, kept identical to the web demo, whose gate
cannot link a macro-plugin dependency; see `WASM.md`), so that round trip is also
the third-backend proof of per-surface `@Reactive` state (ADR 0011).

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
- `MainActivity.kt` — drives resize/key/pointer into the context.

## Building

`ANDROID_NDK_HOME=… ./scripts/check-android.sh` cross-compiles GamaEmbed
and the demo library for both ABIs with the pinned SDK (ids/SHA-256 in
`Toolchains.toml`) and the pinned NDK 30.0.15729638, then packages
`jniLibs` — including the transitive `.so` closure and `libc++_shared.so`,
which the Swift runtime requires at load time.
`scripts/check-android-emulator.sh` is the runtime proof CI runs.
It first exercises the fail-closed readiness policy, enables hosted KVM, and
then requires the input-driven frame assertion. See
[`../Capabilities.md`](../Capabilities.md) for the current evidence boundary.
