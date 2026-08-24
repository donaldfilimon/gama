#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${GAMA_WASM_SDK_ID:-swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-08-14-a_wasm}"
SWIFT="${GAMA_SWIFT_64:-/Users/donaldfilimon/Library/Developer/Toolchains/swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-08-14-a.xctoolchain/usr/bin/swift}"
"$SWIFT" --version | grep -q 'Swift version 6.4'
"$SWIFT" sdk list | grep -Fxq "$SDK" || { echo "error: missing WASM SDK $SDK" >&2; exit 1; }
"$SWIFT" build --package-path "$ROOT" --scratch-path /private/tmp/gama-wasm-swiftpm --swift-sdk "$SDK" --product gama-web-demo \
  -Xlinker --export=gama_web_v1_frame \
  -Xlinker --export=gama_web_v1_key \
  -Xlinker --export=gama_web_v1_pointer \
  -Xlinker --export=gama_web_v1_resize
rg -q 'gama_web_v1_(frame|key|pointer|resize)' "$ROOT/WebHost/gama.js"
artifact="$(find /private/tmp/gama-wasm-swiftpm -type f -name 'gama-web-demo.wasm' -print -quit)"
[[ -n "$artifact" ]] || { echo "error: executable WASM artifact not produced" >&2; exit 1; }
node "$ROOT/scripts/wasm-runtime-smoke.mjs" "$artifact"
node "$ROOT/scripts/browser-runtime-smoke.mjs" "$artifact" "$ROOT/WebHost"
mkdir -p "$ROOT/.build/artifacts"
cp "$artifact" "$ROOT/.build/artifacts/gama-web-demo.wasm"
echo "OK — WASM reactor executable and dependency-free browser runtime"
