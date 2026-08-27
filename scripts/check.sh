#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
gates=(check-apple.sh check-apple-platforms.sh check-boundaries.sh check-concurrency-negative.sh check-c-abi.sh check-embedded.sh check-linux.sh check-wasm.sh check-android.sh check-android-emulator.sh check-mlir.sh check-docs.sh check-doc-coverage.sh)
for gate in "${gates[@]}"; do
  echo "==> ${gate}"
  "$ROOT/scripts/$gate"
done
echo "OK — complete local Gama Framework acceptance matrix"
