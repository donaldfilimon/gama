#!/usr/bin/env bash
set -euo pipefail
unset TOOLCHAINS || true
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH="${GAMA_APPLE_SCRATCH_PATH:-/private/tmp/gama-framework-swiftpm}"
SWIFT=(/usr/bin/xcrun --toolchain default swift)
version="$("${SWIFT[@]}" --version)"
grep -q 'Swift version 6.4' <<<"$version" || { echo "error: Apple gate requires Swift 6.4" >&2; echo "$version" >&2; exit 1; }
"${SWIFT[@]}" build --package-path "$ROOT" --scratch-path "$SCRATCH"
"${SWIFT[@]}" test --package-path "$ROOT" --scratch-path "$SCRATCH"
"${SWIFT[@]}" build -c release --package-path "$ROOT" --scratch-path "$SCRATCH-release"
echo "OK — Apple Swift 6.4 debug/test/release"
