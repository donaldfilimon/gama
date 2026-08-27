#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/Examples/Android"
: "${ANDROID_HOME:?ANDROID_HOME is required for the Android emulator gate}"
command -v adb >/dev/null
command -v gradle >/dev/null
adb get-state | grep -qx device
test -f "$PROJECT/app/src/main/jniLibs/x86_64/libGamaAndroidDemo.so"
(
  cd "$PROJECT"
  gradle --no-daemon :app:assembleDebug
)
apk="$PROJECT/app/build/outputs/apk/debug/app-debug.apk"
test -f "$apk"

# Hosted emulators occasionally report a completed boot and then drop the
# first package-manager transport with `Broken pipe`/exit 224. Keep this gate
# strict about the eventual install while recovering the device connection in
# a bounded way instead of turning a transient adb failure into a false product
# regression.
installed=false
for attempt in 1 2 3; do
  if timeout 90s adb install -r "$apk"; then
    installed=true
    break
  fi
  echo "warning: adb install attempt $attempt failed; reconnecting device" >&2
  adb reconnect >/dev/null 2>&1 || true
  timeout 30s adb wait-for-device || true
  sleep 5
done
if [[ "$installed" != true ]]; then
  echo "error: Android APK install failed after 3 attempts" >&2
  exit 1
fi

adb shell am force-stop com.gama.example
adb logcat -c
adb shell am start -W -n com.gama.example/.MainActivity >/dev/null

for _ in $(seq 1 20); do
  # A wedged accessibility service can otherwise make one dump consume minutes.
  timeout 5s adb shell uiautomator dump /sdcard/gama-window.xml >/dev/null 2>&1 || true
  if adb exec-out cat /sdcard/gama-window.xml 2>/dev/null | grep -q 'GAMA_OK 40 12 CHANGED'; then
    echo "OK — Android emulator JNI input mutated and rendered a decoded frame"
    exit 0
  fi
  if adb logcat -d -s GamaAcceptance:I '*:S' | grep -q 'GAMA_OK 40 12 CHANGED'; then
    echo "OK — Android emulator JNI input mutated and rendered a decoded frame"
    exit 0
  fi
  sleep 1
done
adb logcat -d -t 400 >&2 || true
echo "error: Android UI never exposed the GAMA_OK runtime assertion" >&2
exit 1
