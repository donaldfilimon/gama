#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${GAMA_WASM_SDK_ID:-swift-DEVELOPMENT-SNAPSHOT-2026-08-21-a_wasm}"
SWIFT="${GAMA_SWIFT_64:-/Users/donaldfilimon/Library/Developer/Toolchains/swift-DEVELOPMENT-SNAPSHOT-2026-08-21-a.xctoolchain/usr/bin/swift}"
SCRATCH_ROOT="${GAMA_SCRATCH_ROOT:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}}"
SCRATCH="$SCRATCH_ROOT/gama-wasm-swiftpm"
"$SWIFT" --version | grep -q 'Swift version 6.5'
"$SWIFT" sdk list | grep -Fxq "$SDK" || { echo "error: missing WASM SDK $SDK" >&2; exit 1; }
"$SWIFT" build --package-path "$ROOT" --scratch-path "$SCRATCH" --swift-sdk "$SDK" --product gama-web-demo \
  -Xlinker --export=gama_web_v1_frame \
  -Xlinker --export=gama_web_v1_key \
  -Xlinker --export=gama_web_v1_pointer \
  -Xlinker --export=gama_web_v1_resize \
  -Xlinker --export=gama_web_v2_frame \
  -Xlinker --export=gama_web_v2_key \
  -Xlinker --export=gama_web_v2_pointer \
  -Xlinker --export=gama_web_v2_resize
grep -q -E 'gama_web_v1_(frame|key|pointer|resize)' "$ROOT/WebHost/gama.js"
artifact="$(find "$SCRATCH" -type f -name 'gama-web-demo.wasm' -print -quit)"
[[ -n "$artifact" ]] || { echo "error: executable WASM artifact not produced" >&2; exit 1; }
node "$ROOT/scripts/wasm-runtime-smoke.mjs" "$artifact"
node "$ROOT/scripts/browser-runtime-smoke.mjs" "$artifact" "$ROOT/WebHost"
mkdir -p "$ROOT/.build/artifacts"
cp "$artifact" "$ROOT/.build/artifacts/gama-web-demo.wasm"
echo "OK — WASM reactor executable and dependency-free browser runtime"
