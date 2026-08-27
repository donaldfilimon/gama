#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v mlir-opt >/dev/null || { echo "error: mlir-opt is required" >&2; exit 1; }
OUT="${TMPDIR:-/tmp}/gama-demo.mlir"
unset TOOLCHAINS || true
/usr/bin/xcrun --toolchain "${GAMA_TOOLCHAIN_ID:-org.swift.65202608211a}" swift run --package-path "$ROOT" --scratch-path /private/tmp/gama-framework-swiftpm gama-demo --emit-mlir > "$OUT"
mlir-opt --allow-unregistered-dialect "$OUT" >/dev/null
echo "OK — generic-form gama MLIR parsed by mlir-opt"
