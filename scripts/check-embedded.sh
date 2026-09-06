#!/usr/bin/env bash
set -euo pipefail
unset TOOLCHAINS || true
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/toolchain.sh
source "$ROOT/scripts/lib/toolchain.sh"
SNAP="${GAMA_EMBEDDED_TOOLCHAIN:-}"
[[ -n "$SNAP" ]] || SNAP="$(gama_snapshot_toolchain_dir)" || exit 1
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
# ADR 0008 keeps the canonical pump's *policy* in GamaCore for one stated
# reason: this gate compiles GamaCore alone, so a pump moved into GamaDraw would
# sit outside the Embedded proof while every gate stayed green. The record says
# so; nothing asserted it. The split is deliberate — HostPump.swift is the
# policy and belongs here, HostPump+CellBuffer.swift is the CellBuffer half and
# belongs in GamaDraw, which depends on GamaCore and cannot be Embedded.
[[ -f "$ROOT/Sources/GamaCore/HostPump.swift" ]] || {
  echo "error: Sources/GamaCore/HostPump.swift is missing; ADR 0008 keeps the pump policy in GamaCore precisely so this gate covers it" >&2
  exit 1
}
if compgen -G "$ROOT/Sources/GamaDraw/HostPump.swift" >/dev/null; then
  echo "error: the pump policy moved to GamaDraw; this gate compiles GamaCore alone, so it would no longer prove the pump" >&2
  exit 1
fi
sources=()
while IFS= read -r source; do sources+=("$source"); done < <(find "$ROOT/Sources/GamaCore" -name '*.swift' | sort)
# The find above is what makes the check above meaningful: this gate proves
# exactly the files under Sources/GamaCore and nothing else.
grep -qx "$ROOT/Sources/GamaCore/HostPump.swift" < <(printf '%s\n' "${sources[@]}") || {
  echo "error: HostPump.swift exists but was not collected into the Embedded compile" >&2
  exit 1
}
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

# ADR 0009 names a size gate as its zero-cost evidence. Until 2026-09-06 the
# line above was the whole of it: a number printed and nothing asserted.
BASELINE_FILE="$ROOT/scripts/embedded-size-baseline.txt"
[[ -f "$BASELINE_FILE" ]] || { echo "error: missing size baseline: $BASELINE_FILE" >&2; exit 1; }
base_revision=""; base_bytes=""; base_tolerance=""
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "${line// }" ]] && continue
  [[ "$line" == \#* ]] && continue
  if [[ "$line" =~ ^([a-z_]+)[[:space:]]*=[[:space:]]*\"([^\"]*)\"$ ]]; then
    case "${BASH_REMATCH[1]}" in
      revision) base_revision="${BASH_REMATCH[2]}" ;;
      bytes) base_bytes="${BASH_REMATCH[2]}" ;;
      tolerance_percent) base_tolerance="${BASH_REMATCH[2]}" ;;
      *) echo "error: unknown key in size baseline: ${BASH_REMATCH[1]}" >&2; exit 1 ;;
    esac
  else
    echo "error: unrecognized line in size baseline: $line" >&2
    exit 1
  fi
done < "$BASELINE_FILE"
[[ -n "$base_revision" && -n "$base_bytes" && -n "$base_tolerance" ]] || {
  echo "error: size baseline must set revision, bytes, and tolerance_percent" >&2; exit 1; }
grep -q "Swift $base_revision" <<<"$version" || {
  echo "error: size baseline pins compiler revision $base_revision, which is not the one in use" >&2
  echo "  re-measure the artifact deliberately before bumping the snapshot" >&2
  exit 1; }
margin=$(( base_bytes * base_tolerance / 100 ))
high=$(( base_bytes + margin ))
low=$(( base_bytes - margin ))
if (( bytes > high )); then
  echo "error: Embedded artifact grew to $bytes bytes; baseline $base_bytes +${base_tolerance}% allows $high" >&2
  echo "  this is the regression ADR 0009 cites as its zero-cost evidence" >&2
  echo "  if the growth is intended, re-measure and update $BASELINE_FILE with the reason" >&2
  exit 1
fi
if (( bytes < low )); then
  echo "error: Embedded artifact shrank to $bytes bytes; baseline $base_bytes -${base_tolerance}% allows $low" >&2
  echo "  either a real win worth recording, or the link did not produce the whole module" >&2
  exit 1
fi
echo "OK — Embedded artifact $bytes bytes within ${base_tolerance}% of the pinned $base_bytes"
echo "OK — Embedded GamaCore whole-module compile and relocatable link: $LINKED"
