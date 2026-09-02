#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${GAMA_WASM_SDK_ID:-swift-DEVELOPMENT-SNAPSHOT-2026-08-21-a_wasm}"
SWIFT="${GAMA_SWIFT_64:-/Users/donaldfilimon/Library/Developer/Toolchains/swift-DEVELOPMENT-SNAPSHOT-2026-08-21-a.xctoolchain/usr/bin/swift}"
SCRATCH_ROOT="${GAMA_SCRATCH_ROOT:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}}"
SCRATCH="$SCRATCH_ROOT/gama-wasm-swiftpm"
command -v python3 >/dev/null || {
  echo "error: python3 is required for the GamaWASM unsafe-declaration policy gate" >&2
  exit 1
}
python3 "$ROOT/scripts/check-wasm-unsafe-declarations.py" --self-test
python3 "$ROOT/scripts/check-wasm-unsafe-declarations.py" "$ROOT/Sources/GamaWASM"
"$SWIFT" --version | grep -q 'Swift version 6.5'
"$SWIFT" sdk list | grep -Fxq "$SDK" || { echo "error: missing WASM SDK $SDK" >&2; exit 1; }
# Compile and inspect the portable objects before asking SwiftPM to link the
# executable. This makes an accidental libm dependency fail at its source
# target instead of surfacing later as an opaque wasm-ld error.
"$SWIFT" build --package-path "$ROOT" --scratch-path "$SCRATCH" --swift-sdk "$SDK" --target GamaWASM
for target in GamaCore GamaDraw GamaWASM; do
  objects=()
  while IFS= read -r -d '' object; do objects+=("$object"); done < <(
    find "$SCRATCH" -type f \
      \( -path "*/${target}-t.build/Objects-normal/*/*.o" \
         -o -path "*/${target}.build/*.o" \) -print0
  )
  [[ ${#objects[@]} -gt 0 ]] || { echo "error: no WASM objects produced for $target" >&2; exit 1; }
  GAMA_LLVM_NM="${GAMA_LLVM_NM:-$(dirname "$SWIFT")/llvm-nm}" \
    "$ROOT/scripts/check-portable-symbols.sh" "$target (WASM)" "${objects[@]}"
done
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
