#!/usr/bin/env bash
set -euo pipefail
unset TOOLCHAINS || true
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SNAP="${GAMA_EMBEDDED_TOOLCHAIN:-/Users/donaldfilimon/Library/Developer/Toolchains/swift-DEVELOPMENT-SNAPSHOT-2026-08-21-a.xctoolchain}"
SWIFTC="${GAMA_SWIFTC_64:-$SNAP/usr/bin/swiftc}"
if [[ -n "${GAMA_SWIFTC_64:-}" ]]; then
  EXPECTED_SHA="${GAMA_SWIFTC_SHA256:-}"
else
  EXPECTED_SHA="${GAMA_SWIFTC_SHA256:-dbbd4d7b467ad2f0cc7e451b4f828c76a4ba2ba3cf1b7bb7f5514cee1f9c9188}"
fi
[[ -x "$SWIFTC" ]] || { echo "error: missing Embedded compiler: $SWIFTC" >&2; exit 1; }
if [[ -n "$EXPECTED_SHA" ]]; then
  actual_sha="$(shasum -a 256 "$SWIFTC" | awk '{print $1}')"
  [[ "$actual_sha" == "$EXPECTED_SHA" ]] || { echo "error: Embedded compiler checksum mismatch" >&2; exit 1; }
fi
version="$($SWIFTC --version)"
grep -q 'Swift version 6.5' <<<"$version" || { echo "error: exact Swift 6.5 snapshot required" >&2; exit 1; }
grep -q 'Swift 95c5142e84b82c1' <<<"$version" || { echo "error: wrong Swift 6.5 snapshot revision" >&2; exit 1; }
sources=()
while IFS= read -r source; do sources+=("$source"); done < <(find "$ROOT/Sources/GamaCore" -name '*.swift' | sort)
OUT="${GAMA_EMBEDDED_OUTPUT:-${TMPDIR:-/tmp}/GamaCore.embedded.o}"
LINKED="${GAMA_EMBEDDED_LINKED_OUTPUT:-${OUT%.o}.linked.o}"
mkdir -p "$(dirname "$OUT")"
"$SWIFTC" -target armv7em-none-none-eabi -enable-experimental-feature Embedded -package-name Gama -wmo -parse-as-library -Xfrontend -disable-objc-interop -c "${sources[@]}" -o "$OUT"
test -s "$OUT"
LLD="${GAMA_LLD:-$(dirname "$SWIFTC")/ld.lld}"
[[ -x "$LLD" ]] || { echo "error: matching snapshot ld.lld not found: $LLD" >&2; exit 1; }
"$LLD" -r -o "$LINKED" "$OUT"
test -s "$LINKED"
bytes="$(wc -c < "$LINKED" | tr -d ' ')"
echo "Embedded linked artifact bytes: $bytes"
echo "OK — Embedded GamaCore whole-module compile and relocatable link: $LINKED"
