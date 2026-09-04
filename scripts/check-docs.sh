#!/usr/bin/env bash
# Checks repository Markdown links and the mirrored run-gama skill, then builds every
# `Sources/<Module>/<Module>.docc` catalog with DocC, warnings as errors.
# GamaCore's catalog is required; new catalogs are discovered automatically.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH="${GAMA_DOCC_SCRATCH_PATH:-/private/tmp/gama-docc-swiftpm}"
test -f "$ROOT/Sources/GamaCore/GamaCore.docc/GamaCore.md"
test -f "$ROOT/docs/Capabilities.md"
python3 "$ROOT/scripts/check-doc-links.py" --self-test "$ROOT"
"$ROOT/scripts/check-run-gama-skill.sh"
unset TOOLCHAINS || true
/usr/bin/xcrun --toolchain "${GAMA_TOOLCHAIN_ID:-org.swift.65202608211a}" swift package --package-path "$ROOT" dump-package >/dev/null
(
  cd "$ROOT"
  /usr/bin/xcrun --toolchain "${GAMA_TOOLCHAIN_ID:-org.swift.65202608211a}" swift package --scratch-path "$SCRATCH" dump-symbol-graph --minimum-access-level public
)
built=()
for catalog in "$ROOT"/Sources/*/*.docc; do
  [[ -d "$catalog" ]] || continue
  module="$(basename "$catalog" .docc)"
  if [[ ! -f "$catalog/$module.md" ]]; then
    echo "error: $catalog has no root article $module.md" >&2
    exit 1
  fi
  # The dump emits a single-module directory per target
  # (<Module>.symbolgraphs), which keeps each catalog's docc pass scoped to
  # exactly its own module plus that module's extension graphs.
  symbol_file="$(find "$SCRATCH" -type f -path "*/${module}.symbolgraphs/${module}.symbols.json" -print -quit)"
  [[ -n "$symbol_file" ]] || { echo "error: $module symbol graph was not produced" >&2; exit 1; }
  symbol_dir="$(dirname "$symbol_file")"
  out="$ROOT/.build/docc/$module.doccarchive"
  id_suffix="$(printf '%s' "${module#Gama}" | tr '[:upper:]' '[:lower:]')"
  mkdir -p "$(dirname "$out")"
  rm -rf "$out"
  /usr/bin/xcrun docc convert "$catalog" \
    --additional-symbol-graph-dir "$symbol_dir" \
    --output-path "$out" \
    --fallback-display-name "$module" \
    --fallback-bundle-identifier "com.donaldfilimon.gama.$id_suffix" \
    --fallback-bundle-version 1.0.0 \
    --warnings-as-errors
  module_json="$(printf '%s' "$module" | tr '[:upper:]' '[:lower:]')"
  test -f "$out/data/documentation/$module_json.json"
  built+=("$module")
done
printf '%s\n' "${built[@]}" | grep -qx 'GamaCore' || {
  echo "error: GamaCore catalog was not built" >&2
  exit 1
}
grep -q '^## Status vocabulary' "$ROOT/docs/Capabilities.md"
echo "OK — DocC archives (${built[*]}), package metadata, and claim-honest documentation"
