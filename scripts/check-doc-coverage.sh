#!/usr/bin/env bash
# Fails when any public declaration in a Gama module lacks a doc comment.
# Baseline exceptions (with justifications) live in doc-coverage-allowlist.txt.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH_ROOT="${GAMA_SCRATCH_ROOT:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}}"
SCRATCH="${GAMA_DOC_COVERAGE_SCRATCH_PATH:-$SCRATCH_ROOT/gama-doc-coverage-swiftpm}"
if [[ -n "${GAMA_SWIFT_64:-}" ]]; then
  SWIFT=("$GAMA_SWIFT_64")
else
  unset TOOLCHAINS || true
  SWIFT=(/usr/bin/xcrun --toolchain "${GAMA_TOOLCHAIN_ID:-org.swift.65202608211a}" swift)
fi
(
  cd "$ROOT"
  "${SWIFT[@]}" package --scratch-path "$SCRATCH" dump-symbol-graph \
    --minimum-access-level public >/dev/null
)
python3 "$ROOT/scripts/doc-coverage.py" "$SCRATCH" \
  "$ROOT/scripts/doc-coverage-allowlist.txt"
