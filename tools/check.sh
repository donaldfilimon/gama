#!/usr/bin/env bash
# The gate. Prints "check.sh: PASSED" only after every step succeeds.
# Run as: ./tools/check.sh > check.log 2>&1; echo "EXIT:$?"
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
unset TOOLCHAINS

# Minimum test count. A filter or a target that silently matches nothing
# prints success with zero tests, so the gate asserts a floor. Raise it when
# tests are added; never lower it to make the gate pass.
MIN_TESTS=34
LIBRARY="Sources/GamaAuthoring"
BANNED='Foundation|Darwin|Glibc|simd|RealityKit|SwiftUI|AppKit|UIKit|Combine|Dispatch'

echo "==> toolchain"
version="$(swiftly run swift --version 2>&1)"
grep -q 'Swift version 6.5-dev' <<<"$version" || {
  echo "error: expected the pinned 6.5-dev snapshot, got: $version" >&2; exit 1; }

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

echo "==> build (warnings as errors)"
swiftly run swift build -Xswiftc -warnings-as-errors

echo "==> test"
log="$(mktemp -t gama-studio-test)"
trap 'rm -f "$log"' EXIT
set +e
swiftly run swift test >"$log" 2>&1
status=$?
set -e
cat "$log"
[[ $status -eq 0 ]] || { echo "error: swift test exited $status" >&2; exit 1; }
summary="$(sed 's/\x1b\[[0-9;]*m//g' "$log" | grep -E 'Test run with [0-9]+ tests? .* passed' | tail -1)"
[[ -n "$summary" ]] || { echo "error: no passing Swift Testing summary in the log" >&2; exit 1; }
count="$(sed -E 's/.*Test run with ([0-9]+) tests?.*/\1/' <<<"$summary")"
(( count >= MIN_TESTS )) || { echo "error: ran $count tests, expected at least $MIN_TESTS" >&2; exit 1; }
echo "tests: $count (floor $MIN_TESTS)"

echo "check.sh: PASSED"
