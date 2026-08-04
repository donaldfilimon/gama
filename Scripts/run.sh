#!/usr/bin/env bash
# Build + run Gama with argv forwarded (Xcode `swift run` drops args here).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
unset TOOLCHAINS || true
XCODE_SWIFT="${XCODE_SWIFT:-/Users/donaldfilimon/.grok/skills/swift/scripts/xcode-swift.sh}"
"$XCODE_SWIFT" build --disable-sandbox --product Gama
exec "$ROOT/.build/out/Products/Debug/Gama" "$@"
