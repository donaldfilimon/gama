#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${GAMA_WASM_SDK_ID:-swift-DEVELOPMENT-SNAPSHOT-2026-08-21-a_wasm}"
# shellcheck source=lib/toolchain.sh
source "$ROOT/scripts/lib/toolchain.sh"
SWIFT="${GAMA_SWIFT_64:-}"
[[ -n "$SWIFT" ]] || SWIFT="$(gama_snapshot_swift)" || exit 1
SCRATCH_ROOT="${GAMA_SCRATCH_ROOT:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}}"
SCRATCH="$SCRATCH_ROOT/gama-wasm-swiftpm"
command -v python3 >/dev/null || {
  echo "error: python3 is required for the GamaWASM unsafe-declaration policy gate" >&2
  exit 1
}
python3 "$ROOT/scripts/check-wasm-unsafe-declarations.py" --self-test
python3 "$ROOT/scripts/check-wasm-unsafe-declarations.py" "$ROOT/Sources/GamaWASM"
node "$ROOT/scripts/wasm-runtime-smoke.mjs" --self-test
node "$ROOT/scripts/browser-runtime-smoke.mjs" --self-test
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
"$SWIFT" build --package-path "$ROOT" --scratch-path "$SCRATCH" --swift-sdk "$SDK" --product gama-web-demo
# The browser host is v2-only: every event reaches the module through a
# status-returning export, which is what lets the page name a failed install.
# All four calls are required individually — an alternation would pass with
# one — and any remaining v1 call fails closed, so a half-migration cannot.
for event in frame key pointer resize; do
  grep -q "exports\.gama_web_v2_${event}(" "$ROOT/WebHost/gama.js" || {
    echo "error: WebHost/gama.js does not call gama_web_v2_${event}" >&2
    exit 1
  }
done
if grep -q 'exports\.gama_web_v1_' "$ROOT/WebHost/gama.js"; then
  echo "error: WebHost/gama.js still calls a gama_web_v1_ export; the host is v2-only" >&2
  exit 1
fi
artifact="$(find "$SCRATCH" -type f -name 'gama-web-demo.wasm' -print -quit)"
[[ -n "$artifact" ]] || { echo "error: executable WASM artifact not produced" >&2; exit 1; }
"$SWIFT" build --package-path "$ROOT" --scratch-path "$SCRATCH" --swift-sdk "$SDK" --product GamaWASMFailedInstall
failed_install_artifact="$(find "$SCRATCH" -type f -name 'GamaWASMFailedInstall.wasm' -print -quit)"
[[ -n "$failed_install_artifact" ]] || { echo "error: failed-install WASM fixture not produced" >&2; exit 1; }
node "$ROOT/scripts/wasm-runtime-smoke.mjs" "$failed_install_artifact" --failed-install
# The same fixture through the real page: only a host that reads v2 statuses
# can report the missing host instead of hanging on its boot overlay.
node "$ROOT/scripts/browser-runtime-smoke.mjs" "$failed_install_artifact" "$ROOT/WebHost" --failed-install
node "$ROOT/scripts/wasm-runtime-smoke.mjs" "$artifact"
node "$ROOT/scripts/browser-runtime-smoke.mjs" "$artifact" "$ROOT/WebHost"
mkdir -p "$ROOT/.build/artifacts"
cp "$artifact" "$ROOT/.build/artifacts/gama-web-demo.wasm"
echo "OK — WASM reactor executable and dependency-free browser runtime"
