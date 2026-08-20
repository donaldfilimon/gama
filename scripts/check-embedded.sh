#!/usr/bin/env bash
# Compile GamaCore with Embedded Swift (OSS snapshot). Not the TUI gate.
set -euo pipefail
unset TOOLCHAINS || true
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SNAP="${GAMA_EMBEDDED_TOOLCHAIN:-/Users/donaldfilimon/Library/Developer/Toolchains/swift-DEVELOPMENT-SNAPSHOT-2026-08-11-a.xctoolchain}"
SWIFTC="$SNAP/usr/bin/swiftc"
if [[ ! -x "$SWIFTC" ]]; then
  echo "error: Embedded snapshot swiftc missing at $SWIFTC" >&2
  exit 1
fi
sources=()
while IFS= read -r f; do
  sources+=("$f")
done < <(find "$ROOT/Sources/GamaCore" -name '*.swift' | sort)
if [[ ${#sources[@]} -eq 0 ]]; then
  echo "error: no GamaCore sources" >&2
  exit 1
fi
OUT="${TMPDIR:-/tmp}/GamaCore.embedded.o"
"$SWIFTC" \
  -target arm64-apple-none-macho \
  -enable-experimental-feature Embedded \
  -wmo -parse-as-library \
  -Xfrontend -disable-objc-interop \
  -c "${sources[@]}" \
  -o "$OUT"
test -s "$OUT"
echo "OK — GamaCore Embedded object at $OUT"
