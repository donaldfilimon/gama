#!/usr/bin/env bash
set -euo pipefail
unset TOOLCHAINS || true

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLCHAIN="${GAMA_TOOLCHAIN_ID:-org.swift.65202608211a}"
SWIFT=(/usr/bin/xcrun --toolchain "$TOOLCHAIN" swift)
SWIFTC="${GAMA_SWIFTC_64:-$(/usr/bin/xcrun --toolchain "$TOOLCHAIN" --find swiftc)}"
SCRATCH="${GAMA_CONCURRENCY_NEGATIVE_SCRATCH_PATH:-/private/tmp/gama-concurrency-negative}"

version="$("${SWIFT[@]}" --version)"
grep -q 'Swift version 6.5' <<<"$version" || {
  echo "error: concurrency negatives require Swift 6.5" >&2
  echo "$version" >&2
  exit 1
}
grep -q 'Swift 95c5142e84b82c1' <<<"$version" || {
  echo "error: concurrency negatives require the pinned Swift snapshot" >&2
  echo "$version" >&2
  exit 1
}

"${SWIFT[@]}" build --package-path "$ROOT" --scratch-path "$SCRATCH" \
  --target GamaPlugin >/dev/null

module_dir=""
while IFS= read -r module; do
  candidate="$(dirname "$module")"
  if [[ -e "$candidate/GamaPlugin.swiftmodule" ]]; then
    module_dir="$candidate"
    break
  fi
done < <(find "$SCRATCH" -name GamaCore.swiftmodule -print)
[[ -n "$module_dir" ]] || {
  echo "error: compiled GamaCore/GamaPlugin modules were not found" >&2
  exit 1
}

fixtures=(
  "SignalSendable.swift:Signal"
  "PluginRuntimeSendable.swift:PluginRuntime"
)
for specification in "${fixtures[@]}"; do
  fixture_name="${specification%%:*}"
  type_name="${specification#*:}"
  fixture="$ROOT/Tests/CompileFail/$fixture_name"

  output="$("$SWIFTC" -typecheck -swift-version 6 -I "$module_dir" "$fixture" 2>&1)" \
    && status=0 || status=$?
  if [[ $status -eq 0 ]]; then
    echo "error: concurrency negative compiled but must fail: $fixture_name" >&2
    exit 1
  fi
  grep -Fq "$type_name" <<<"$output" || {
    echo "error: $fixture_name failed without identifying $type_name" >&2
    echo "$output" >&2
    exit 1
  }
  grep -Fq "to 'Sendable' is unavailable" <<<"$output" || {
    echo "error: $fixture_name did not diagnose the unavailable Sendable conformance" >&2
    echo "$output" >&2
    exit 1
  }
  grep -Fq "has been explicitly marked unavailable here" <<<"$output" || {
    echo "error: $fixture_name did not point to the unavailable conformance" >&2
    echo "$output" >&2
    exit 1
  }
done

echo "OK — pinned concurrency negatives (Signal, PluginRuntime)"
