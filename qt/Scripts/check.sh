#!/usr/bin/env bash
# Repository gate: build, then test, through the Xcode default toolchain.
# Prints "build EXIT:<n>" and "test EXIT:<n>"; exits nonzero if either failed.
# Redirect to a log and read this script's own exit code (never pipe it).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
unset TOOLCHAINS || true
# Prefer the machine-local xcode-swift wrapper (same default as Scripts/run.sh);
# fall back to plain `xcrun swift` so the gate works on any machine with Xcode.
XCODE_SWIFT="${XCODE_SWIFT:-/Users/donaldfilimon/.grok/skills/swift/scripts/xcode-swift.sh}"
if [ -x "$XCODE_SWIFT" ]; then
  SWIFT=("$XCODE_SWIFT")
else
  SWIFT=(xcrun swift)
fi

"${SWIFT[@]}" build
build_rc=$?
echo "build EXIT:$build_rc"
if [ "$build_rc" -ne 0 ]; then
  echo "check.sh: FAILED (build)"
  exit "$build_rc"
fi

"${SWIFT[@]}" test
test_rc=$?
echo "test EXIT:$test_rc"
if [ "$test_rc" -ne 0 ]; then
  echo "check.sh: FAILED (test)"
  exit "$test_rc"
fi

echo "check.sh: PASSED"
