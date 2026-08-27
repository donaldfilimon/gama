#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SWIFT="${GAMA_SWIFT_64:-swift}"
SCRATCH_ROOT="${GAMA_SCRATCH_ROOT:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}}"
SCRATCH_PATH="$SCRATCH_ROOT/gama-linux-leaks-swiftpm"
EVIDENCE_PATH="$SCRATCH_ROOT/gama-linux-leaks-evidence"

if [[ "$(uname -s)" != Linux ]]; then
  echo "error: LeakSanitizer leak detection is a hosted Linux proof; macOS can only build and run gama-leak-check without LSan" >&2
  exit 2
fi

"$SWIFT" --version | grep -q 'Swift version 6.5'
mkdir -p "$EVIDENCE_PATH"

# Build once with ASan instrumentation, then execute the product directly.
# `swift test` and `swift run` are intentionally absent: neither Swift
# Testing nor XCTest may sit above the allocation stacks this gate audits.
"$SWIFT" build \
  --package-path "$ROOT" \
  --scratch-path "$SCRATCH_PATH" \
  --sanitize address \
  --product gama-leak-check
BIN_DIR="$("$SWIFT" build \
  --package-path "$ROOT" \
  --scratch-path "$SCRATCH_PATH" \
  --sanitize address \
  --show-bin-path)"
PROBE="$BIN_DIR/gama-leak-check"
CLEAN_LOG="$EVIDENCE_PATH/clean.log"
NEGATIVE_LOG="$EVIDENCE_PATH/negative-control.log"

[[ -x "$PROBE" ]] || { echo "error: missing leak-check executable: $PROBE" >&2; exit 1; }

# Do not inherit or install suppressions. The clean Gama lifecycle must exit
# zero with leak detection genuinely enabled.
ASAN_OPTIONS='detect_leaks=1:halt_on_error=1' \
LSAN_OPTIONS='exitcode=86' \
  "$PROBE" >"$CLEAN_LOG" 2>&1
grep -Fq 'GAMA_LEAK_CHECK_CLEAN_PATH_COMPLETE' "$CLEAN_LOG"
if grep -Fq 'LeakSanitizer: detected memory leaks' "$CLEAN_LOG"; then
  cat "$CLEAN_LOG" >&2
  echo "error: harness-free Gama lifecycle leaked" >&2
  exit 1
fi

# The same instrumented binary must fail only when its deliberate GamaCore
# Signal leak is armed. Exit 86 is LSan's configured result, and the two log
# markers prove this was the intended detector failure rather than a crash.
set +e
ASAN_OPTIONS='detect_leaks=1:halt_on_error=1' \
LSAN_OPTIONS='exitcode=86' \
  "$PROBE" --deliberate-leak >"$NEGATIVE_LOG" 2>&1
negative_status=$?
set -e

if [[ $negative_status -ne 86 ]]; then
  cat "$NEGATIVE_LOG" >&2
  echo "error: deliberate leak returned $negative_status; expected LeakSanitizer exit 86" >&2
  exit 1
fi
grep -Fq 'GAMA_LEAK_NEGATIVE_CONTROL_ARMED' "$NEGATIVE_LOG"
grep -Fq 'LeakSanitizer: detected memory leaks' "$NEGATIVE_LOG"

echo "clean-path exit=0 marker=GAMA_LEAK_CHECK_CLEAN_PATH_COMPLETE"
echo "negative-control exit=$negative_status marker=GAMA_LEAK_NEGATIVE_CONTROL_ARMED"
grep -Fm1 'LeakSanitizer: detected memory leaks' "$NEGATIVE_LOG"
echo "OK — harness-free Linux LeakSanitizer clean path and failing negative control"
