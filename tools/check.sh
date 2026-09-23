#!/usr/bin/env bash
# The gate. Prints "check.sh: PASSED" only after every step succeeds.
# Run as: ./tools/check.sh >| check.log 2>&1; echo "EXIT:$?"
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
unset TOOLCHAINS

# Minimum test count. A filter or a target that silently matches nothing
# prints success with zero tests, so the gate asserts a floor. Raise it when
# tests are added; never lower it to make the gate pass.
MIN_TESTS=173
# Standard-library-only targets (ADR 0001, ADR 0005).
LIBRARIES=("Sources/GamaAuthoring" "Sources/GamaUSD")
BANNED='Foundation|Darwin|Glibc|simd|RealityKit|SwiftUI|AppKit|UIKit|Combine|Dispatch'

echo "==> toolchain"
version="$(swiftly run swift --version 2>&1)"
grep -q 'Swift version 6.5-dev' <<<"$version" || {
  echo "error: expected the pinned 6.5-dev snapshot, got: $version" >&2; exit 1; }

for LIBRARY in "${LIBRARIES[@]}"; do
echo "==> portable-import ban ($LIBRARY)"
# Fail closed: BSD grep over a missing path exits 1 with no output, which
# would read as "no violation".
[[ -d "$LIBRARY" ]] || { echo "error: $LIBRARY is missing" >&2; exit 1; }
sources=()
while IFS= read -r file; do sources+=("$file"); done < <(find "$LIBRARY" -name '*.swift' | sort)
[[ ${#sources[@]} -gt 0 ]] || { echo "error: no Swift sources under $LIBRARY" >&2; exit 1; }
# grep exits 0 on a match, 1 on none, and 2 or more on its own failure; only
# exit 1 is a clean result, so the code is captured rather than tested in `if`.
set +e
hits="$(grep -n -E "^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*((public|package|internal|fileprivate|private)[[:space:]]+)?import[[:space:]]+(struct[[:space:]]+|class[[:space:]]+|enum[[:space:]]+|func[[:space:]]+|protocol[[:space:]]+)?($BANNED)\b" "${sources[@]}")"
rc=$?
set -e
case $rc in
  0) echo "$hits" >&2
     echo "error: $LIBRARY must stay standard-library-only (ADR 0001)" >&2; exit 1 ;;
  1) ;;
  *) echo "error: import scan failed (grep exit $rc)" >&2; exit 1 ;;
esac
done

echo "==> build (warnings as errors)"
swiftly run swift build -Xswiftc -warnings-as-errors

echo "==> test"
log="$(mktemp -t gama-studio-test)"
trap 'rm -f "$log"' EXIT
set +e
swiftly run swift test >"$log" 2>&1 </dev/null
status=$?
set -e
cat "$log"
[[ $status -eq 0 ]] || { echo "error: swift test exited $status" >&2; exit 1; }
# Swift Testing prints one summary per test target; every one must pass and
# the floor applies to their sum.
plain="$(sed 's/\x1b\[[0-9;]*m//g' "$log")"
if grep -E 'Test run with [0-9]+ tests? .* failed' <<<"$plain"; then
  echo "error: a Swift Testing run failed" >&2; exit 1
fi
summaries="$(grep -E 'Test run with [0-9]+ tests? .* passed' <<<"$plain" || true)"
[[ -n "$summaries" ]] || { echo "error: no passing Swift Testing summary in the log" >&2; exit 1; }
count=0
while IFS= read -r line; do
  count=$(( count + $(sed -E 's/.*Test run with ([0-9]+) tests?.*/\1/' <<<"$line") ))
done <<<"$summaries"
(( count >= MIN_TESTS )) || { echo "error: ran $count tests, expected at least $MIN_TESTS" >&2; exit 1; }
echo "tests: $count (floor $MIN_TESTS)"

echo "==> smoke"
# Launches the real executable headless: one frame, the RealityKit viewport
# attached to its native region, and the sample scene projected. The exit
# code is checked directly, never through a pipe.
set +e
swiftly run swift run gama-studio --smoke </dev/null
status=$?
set -e
[[ $status -eq 0 ]] || { echo "error: gama-studio --smoke exited $status" >&2; exit 1; }

echo "==> usd"
# Writes the sample scene headlessly, validates it with Apple's USD tools,
# lets usdcat reformat it, then reads that back and re-exports: the writer is
# deterministic, so byte equality of the two exports means the reformatted
# file described the same document. Fails closed without the tools.
for tool in usdchecker usdcat; do
  command -v "$tool" >/dev/null || { echo "error: $tool is required for the usd stage (Apple USD Tools)" >&2; exit 1; }
done
usd_dir="$(mktemp -d -t gama-studio-usd)"
trap 'rm -f "$log"; rm -rf "$usd_dir"' EXIT
swiftly run swift run gama-studio --export "$usd_dir/sample.usda" </dev/null
checker="$(usdchecker "$usd_dir/sample.usda" 2>&1)" || { echo "$checker" >&2; echo "error: usdchecker rejected the export" >&2; exit 1; }
grep -q 'Success!' <<<"$checker" || { echo "$checker" >&2; echo "error: usdchecker did not report Success!" >&2; exit 1; }
# The goldens cover what the sample cannot: nested gprims, a light first
# root with materials, component children, and awkward names.
goldens=(Tests/GamaUSDTests/Fixtures/*.usda)
[[ -e "${goldens[0]}" ]] || { echo "error: no USDA goldens under Tests/GamaUSDTests/Fixtures" >&2; exit 1; }
for golden in "${goldens[@]}"; do
  checker="$(usdchecker "$golden" 2>&1)" || { echo "$checker" >&2; echo "error: usdchecker rejected $golden" >&2; exit 1; }
  grep -q 'Success!' <<<"$checker" || { echo "$checker" >&2; echo "error: usdchecker did not report Success! for $golden" >&2; exit 1; }
done
usdcat "$usd_dir/sample.usda" -o "$usd_dir/reformatted.usda"
swiftly run swift run gama-studio --open "$usd_dir/reformatted.usda" --export "$usd_dir/again.usda" </dev/null
cmp "$usd_dir/sample.usda" "$usd_dir/again.usda" || { echo "error: usdcat round trip changed the document" >&2; exit 1; }
echo "usd: usdchecker Success! (sample + ${#goldens[@]} goldens), usdcat round trip identical"

echo "check.sh: PASSED"
