#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH="${GAMA_C_ABI_SCRATCH_PATH:-/private/tmp/gama-c-abi-swiftpm}"
OUT="${TMPDIR:-/tmp}/gama-c-consumer.o"
EXE="${TMPDIR:-/tmp}/gama-c-consumer"
if [[ -n "${GAMA_SWIFT_64:-}" ]]; then
  SWIFT=("$GAMA_SWIFT_64")
  SWIFTC=("$(dirname "$GAMA_SWIFT_64")/swiftc")
else
  unset TOOLCHAINS || true
  SWIFT=(/usr/bin/xcrun --toolchain default swift)
  SWIFTC=(/usr/bin/xcrun --toolchain default swiftc)
fi
"${SWIFT[@]}" build --package-path "$ROOT" --scratch-path "$SCRATCH" --product GamaEmbed
cc -std=c17 -Wall -Wextra -Werror \
  -I"$ROOT/Sources/GamaEmbedABI/include" \
  -c "$ROOT/Examples/CEmbed/main.c" \
  -o "$OUT"
library="$(find "$SCRATCH" -type f -name 'libGamaEmbed.a' -print -quit)"
[[ -n "$library" ]]
"${SWIFTC[@]}" "$OUT" "$library" -o "$EXE"
"$EXE"
echo "OK — versioned C ABI consumer compile, link, and run"
