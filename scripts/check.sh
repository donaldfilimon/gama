#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
zig=${GAMA_ZIG:-zig}
if [[ -n ${GAMA_MLIR_OPT:-} ]]; then set -- "-Dmlir-opt=$GAMA_MLIR_OPT" "$@"; fi
"$zig" build check -j2 "$@"
echo 'check.sh: PASSED'
