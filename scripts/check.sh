#!/usr/bin/env bash
# Gate A: build + test gama with XcodeDefault (ignore swiftly / TOOLCHAINS).
# Gate B is scripts/check-embedded.sh — this script does not prove Embedded.
set -euo pipefail
unset TOOLCHAINS || true
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
SWIFT=(/usr/bin/xcrun --toolchain default swift)
"${SWIFT[@]}" build --package-path "$ROOT"
"${SWIFT[@]}" test --package-path "$ROOT"
echo "OK — Gate A: GamaCoreTests + GamaTUITests + gamaTests (via ${SWIFT[*]})"
echo "Note: Gate B is ./scripts/check-embedded.sh (not covered here)"
