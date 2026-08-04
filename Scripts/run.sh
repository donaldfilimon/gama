#!/usr/bin/env bash
# Build + run Gama with argv forwarded (Xcode `swift run` drops args here).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
unset TOOLCHAINS || true
# Prefer the machine-local xcode-swift wrapper when present; fall back to
# plain `xcrun swift` so the script works on any machine/CI with Xcode.
XCODE_SWIFT="${XCODE_SWIFT:-/Users/donaldfilimon/.grok/skills/swift/scripts/xcode-swift.sh}"
if [ -x "$XCODE_SWIFT" ]; then
  "$XCODE_SWIFT" build --disable-sandbox --product Gama
  exec "$ROOT/.build/out/Products/Debug/Gama" "$@"
else
  xcrun swift build --disable-sandbox --product Gama
  exec "$ROOT/.build/debug/Gama" "$@"
fi
