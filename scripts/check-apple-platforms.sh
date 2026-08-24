#!/usr/bin/env bash
set -euo pipefail

unset TOOLCHAINS || true
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
version="$(/usr/bin/xcrun --toolchain default swift --version)"
grep -q 'Swift version 6.4' <<<"$version" || { echo "error: Apple platform gate requires Swift 6.4" >&2; exit 1; }

platforms=("iOS Simulator" "tvOS Simulator" "visionOS Simulator")
for platform in "${platforms[@]}"; do
  slug="$(tr '[:upper:] ' '[:lower:]-' <<<"$platform")"
  xcodebuild \
    -scheme GamaAppleUI \
    -destination "generic/platform=$platform" \
    -derivedDataPath "/private/tmp/gama-${slug}-derived" \
    CODE_SIGNING_ALLOWED=NO \
    -quiet \
    build
done

echo "OK — iOS, tvOS, and visionOS GamaAppleUI compile gates"
