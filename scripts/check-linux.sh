#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${GAMA_LINUX_SDK_ID:-swift-DEVELOPMENT-SNAPSHOT-2026-08-21-a_static-linux-0.1.0}"
SWIFT="${GAMA_SWIFT_64:-/Users/donaldfilimon/Library/Developer/Toolchains/swift-DEVELOPMENT-SNAPSHOT-2026-08-21-a.xctoolchain/usr/bin/swift}"
SCRATCH_ROOT="${GAMA_SCRATCH_ROOT:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}}"
"$SWIFT" --version | grep -q 'Swift version 6.5'
"$SWIFT" sdk list | grep -Fxq "$SDK" || { echo "error: missing Linux SDK $SDK" >&2; exit 1; }
"$SWIFT" build --package-path "$ROOT" --scratch-path "$SCRATCH_ROOT/gama-linux-swiftpm" --swift-sdk "$SDK" --triple aarch64-swift-linux-musl --target GamaCore
objects=()
while IFS= read -r -d '' object; do objects+=("$object"); done < <(
  find "$SCRATCH_ROOT/gama-linux-swiftpm" -type f \
    \( -path '*/GamaCore-t.build/Objects-normal/*/*.o' \
       -o -path '*/GamaCore.build/*.o' \) -print0
)
[[ ${#objects[@]} -gt 0 ]] || { echo "error: no static-Linux GamaCore objects produced" >&2; exit 1; }
GAMA_LLVM_NM="${GAMA_LLVM_NM:-$(dirname "$SWIFT")/llvm-nm}" \
  "$ROOT/scripts/check-portable-symbols.sh" 'GamaCore (static Linux)' "${objects[@]}"

# Regression proof for the original failure class. x86_64 static Linux emits
# a direct `round` reference for this rounded-then-converted expression, while
# the pinned macOS debug compiler exposes the same dependency as
# `_roundSlowPath` in check-boundaries.sh.
fixture_scratch="${GAMA_PORTABLE_SYMBOL_FIXTURE_SCRATCH_PATH:-$SCRATCH_ROOT/gama-portable-symbol-fixture-swiftpm}"
"$SWIFT" build --package-path "$ROOT/Tests/Fixtures/PortableSymbols" \
  --scratch-path "$fixture_scratch" --swift-sdk "$SDK" \
  --triple x86_64-swift-linux-musl --target RoundedRequiresLibm >/dev/null
fixture_objects=()
while IFS= read -r -d '' object; do fixture_objects+=("$object"); done < <(
  find "$fixture_scratch" -type f \
    \( -path '*/RoundedRequiresLibm-t.build/Objects-normal/*/*.o' \
       -o -path '*/RoundedRequiresLibm.build/*.o' \) -print0
)
[[ ${#fixture_objects[@]} -gt 0 ]] || {
  echo "error: no static-Linux RoundedRequiresLibm fixture objects produced" >&2; exit 1
}
if fixture_output="$(GAMA_LLVM_NM="${GAMA_LLVM_NM:-$(dirname "$SWIFT")/llvm-nm}" \
  "$ROOT/scripts/check-portable-symbols.sh" \
  'PortableSymbols/RoundedRequiresLibm.swift (static Linux)' \
  "${fixture_objects[@]}" 2>&1)"; then
  echo "error: static-Linux portable-symbol negative fixture passed but must fail" >&2; exit 1
fi
grep -q "reference 'round'.*RoundedRequiresLibm" <<<"$fixture_output" || {
  echo "error: static-Linux fixture failed without naming target and round" >&2; exit 1
}
echo "OK — static-Linux portable-symbol negative (RoundedRequiresLibm -> round)"
echo "OK — Linux SDK build"
