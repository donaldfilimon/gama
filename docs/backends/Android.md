# Android backend (JNI over GamaEmbed)

Status: Locally runtime proven with the pinned Android Swift SDK
(arm64-v8a/x86_64 payloads) and hosted proven by the required API 36
emulator input/frame round trip (`Tapped 0` → `Tapped 1`). adb install
"Broken pipe" failures on the hosted job are known infra flakes, not
product failures — rerun the job.

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
