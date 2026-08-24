#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${GAMA_ANDROID_SDK_ID:-swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-08-14-a_android}"
SWIFT="${GAMA_SWIFT_64:-/Users/donaldfilimon/Library/Developer/Toolchains/swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-08-14-a.xctoolchain/usr/bin/swift}"
SCRATCH_ROOT="${GAMA_SCRATCH_ROOT:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}}"
EMBED_SCRATCH="$SCRATCH_ROOT/gama-android-swiftpm"
EMULATOR_SCRATCH="$SCRATCH_ROOT/gama-android-emulator-swiftpm"
DEVICE_SCRATCH="$SCRATCH_ROOT/gama-android-device-swiftpm"
ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"
[[ -n "$ANDROID_NDK_HOME" ]] || { echo "error: ANDROID_NDK_HOME is required" >&2; exit 1; }
export ANDROID_NDK_HOME
"$SWIFT" --version | grep -q 'Swift version 6.4'
"$SWIFT" sdk list | grep -Fxq "$SDK" || { echo "error: missing Android SDK $SDK" >&2; exit 1; }
"$SWIFT" build --package-path "$ROOT" --scratch-path "$EMBED_SCRATCH" --swift-sdk "$SDK" --triple aarch64-unknown-linux-android28 --product GamaEmbed
"$SWIFT" build -c release --package-path "$ROOT" --scratch-path "$EMULATOR_SCRATCH" --swift-sdk "$SDK" --triple x86_64-unknown-linux-android28 --product GamaAndroidDemo
"$SWIFT" build -c release --package-path "$ROOT" --scratch-path "$DEVICE_SCRATCH" --swift-sdk "$SDK" --triple aarch64-unknown-linux-android28 --product GamaAndroidDemo

product="$(find "$EMULATOR_SCRATCH" -type f -name 'libGamaAndroidDemo.so' -print -quit)"
[[ -n "$product" ]] || { echo "error: Android demo shared library was not produced" >&2; exit 1; }
jni="$ROOT/Examples/Android/app/src/main/jniLibs/x86_64"
rm -rf "$jni"
mkdir -p "$jni"
cp "$product" "$jni/"

runtime="$(find -L "$HOME/Library/org.swift.swiftpm/swift-sdks" "$HOME/.swiftpm/swift-sdks" \
  -type f -path '*/swift-x86_64/android/libswiftCore.so' -print -quit 2>/dev/null || true)"
[[ -n "$runtime" ]] || { echo "error: x86_64 Android Swift runtime was not found" >&2; exit 1; }
runtime="$(dirname "$runtime")"
host_tag="linux-x86_64"
[[ "$(uname -s)" == Darwin ]] && host_tag="darwin-x86_64"
readelf="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/$host_tag/bin/llvm-readelf"
[[ -x "$readelf" ]] || { echo "error: missing llvm-readelf at $readelf" >&2; exit 1; }

# Resolve only Swift shared-library dependencies actually referenced by the
# sample, including dependencies of dependencies. Android system libraries are
# deliberately not copied into the APK.
while :; do
  copied=0
  while IFS= read -r needed; do
    [[ -f "$runtime/$needed" && ! -f "$jni/$needed" ]] || continue
    cp "$runtime/$needed" "$jni/$needed"
    copied=1
  done < <(for library in "$jni"/*.so; do
    "$readelf" -d "$library" | sed -n 's/.*Shared library: \[\([^]]*\)\].*/\1/p'
  done | sort -u)
  [[ "$copied" == 0 ]] && break
done

test -f "$jni/libswiftCore.so"
cp "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/$host_tag/sysroot/usr/lib/x86_64-linux-android/libc++_shared.so" "$jni/"

arm_product="$(find "$DEVICE_SCRATCH" -type f -name 'libGamaAndroidDemo.so' -print -quit)"
[[ -n "$arm_product" ]] || { echo "error: arm64 Android demo shared library was not produced" >&2; exit 1; }
arm_jni="$ROOT/Examples/Android/app/src/main/jniLibs/arm64-v8a"
rm -rf "$arm_jni"
mkdir -p "$arm_jni"
cp "$arm_product" "$arm_jni/"
arm_runtime="$(find -L "$HOME/Library/org.swift.swiftpm/swift-sdks" "$HOME/.swiftpm/swift-sdks" \
  -type f -path '*/swift-aarch64/android/libswiftCore.so' -print -quit 2>/dev/null || true)"
[[ -n "$arm_runtime" ]] || { echo "error: aarch64 Android Swift runtime was not found" >&2; exit 1; }
arm_runtime="$(dirname "$arm_runtime")"
while :; do
  copied=0
  while IFS= read -r needed; do
    [[ -f "$arm_runtime/$needed" && ! -f "$arm_jni/$needed" ]] || continue
    cp "$arm_runtime/$needed" "$arm_jni/$needed"
    copied=1
  done < <(for library in "$arm_jni"/*.so; do
    "$readelf" -d "$library" | sed -n 's/.*Shared library: \[\([^]]*\)\].*/\1/p'
  done | sort -u)
  [[ "$copied" == 0 ]] && break
done
test -f "$arm_jni/libswiftCore.so"
cp "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/$host_tag/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so" "$arm_jni/"
echo "OK — Android arm64 GamaEmbed plus x86_64 and arm64-v8a emulator JNI payloads"
