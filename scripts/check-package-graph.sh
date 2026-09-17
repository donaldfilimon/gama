#!/usr/bin/env bash
# Assert the manifest properties three settled decisions rely on: ADR 0012's
# strict-memory-safety scope, the zero-runtime-package-dependency guarantee,
# and the scoping of experimental features. All three were previously enforced
# only by whoever remembered to type them into Package.swift.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="${TMPDIR:-/tmp}/gama-dump-package.$$.json"
trap 'rm -f "$MANIFEST"' EXIT

/usr/bin/xcrun --toolchain "${GAMA_TOOLCHAIN_ID:-org.swift.65202608211a}" \
  swift package --package-path "$ROOT" dump-package >"$MANIFEST"

python3 "$ROOT/scripts/package-graph.py" --self-test --manifest "$MANIFEST" "$ROOT"
