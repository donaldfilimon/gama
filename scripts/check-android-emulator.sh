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
adb install -r "$apk" >/dev/null
adb shell am force-stop com.gama.example
adb shell am start -W -n com.gama.example/.MainActivity >/dev/null

for _ in $(seq 1 20); do
  adb shell uiautomator dump /sdcard/gama-window.xml >/dev/null 2>&1 || true
  if adb exec-out cat /sdcard/gama-window.xml 2>/dev/null | grep -q 'GAMA_OK 40 12 CHANGED'; then
    echo "OK — Android emulator JNI input mutated and rendered a decoded frame"
    exit 0
  fi
  sleep 1
done
adb logcat -d -t 200 '*:E' >&2 || true
echo "error: Android UI never exposed the GAMA_OK runtime assertion" >&2
exit 1
