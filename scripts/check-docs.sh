#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/.build/docc/GamaCore.doccarchive"
SCRATCH="${GAMA_DOCC_SCRATCH_PATH:-/private/tmp/gama-docc-swiftpm}"
test -f "$ROOT/Sources/GamaCore/GamaCore.docc/GamaCore.md"
test -f "$ROOT/docs/Capabilities.md"
unset TOOLCHAINS || true
/usr/bin/xcrun --toolchain default swift package --package-path "$ROOT" dump-package >/dev/null
(
  cd "$ROOT"
  /usr/bin/xcrun --toolchain default swift package --scratch-path "$SCRATCH" dump-symbol-graph --minimum-access-level public
)
symbol_file="$(find "$SCRATCH" -type f -name 'GamaCore.symbols.json' -print -quit)"
[[ -n "$symbol_file" ]] || { echo "error: GamaCore symbol graph was not produced" >&2; exit 1; }
symbol_dir="$(dirname "$symbol_file")"
mkdir -p "$(dirname "$OUT")"
rm -rf "$OUT"
/usr/bin/xcrun docc convert "$ROOT/Sources/GamaCore/GamaCore.docc" \
  --additional-symbol-graph-dir "$symbol_dir" \
  --output-path "$OUT" \
  --fallback-display-name GamaCore \
  --fallback-bundle-identifier com.donaldfilimon.gama.core \
  --fallback-bundle-version 1.0.0 \
  --warnings-as-errors
test -f "$OUT/data/documentation/gamacore.json"
grep -q -E 'Current|Blocked|Proven' "$ROOT/docs/Capabilities.md"
echo "OK — DocC archive, package metadata, and claim-honest documentation"
