#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Catches every import spelling: plain, indented, access-scoped
# (`public import`), attributed (`@preconcurrency`, `@_implementationOnly`),
# and submodule/decl imports (`import struct Foundation.Data`). The old
# anchored `^import X$` form was blind to all but the plain spelling.
if grep -R -n -E --include='*.swift' \
  '^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*(public|package|internal|private|fileprivate)?[[:space:]]*import[[:space:]]+((struct|class|enum|protocol|typealias|func|var|let)[[:space:]]+)?(Foundation|AppKit|UIKit|Darwin|Glibc|WinSDK|Synchronization)\b' \
  "$ROOT/Sources/GamaCore" "$ROOT/Sources/GamaPlugin"; then
  echo "error: GamaCore/GamaPlugin imported a platform/runtime module" >&2; exit 1
fi
if grep -R -n -E --include='*.swift' 'ActionRegistry|Invalidator\.shared|nonisolated\(unsafe\).*_host' "$ROOT/Sources/GamaCore" "$ROOT/Sources/GamaPlugin" "$ROOT/Sources/GamaEmbed"; then
  echo "error: process-global framework state detected" >&2; exit 1
fi
# Inverse boundary: GamaPlatformServices (Foundation-backed service
# implementations) must never leak into a portable or framework target.
# Only demos, examples, and tests may import it.
if grep -R -n -E --include='*.swift' \
  '^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*(public|package|internal|private|fileprivate)?[[:space:]]*import[[:space:]]+((struct|class|enum|protocol|typealias|func|var|let)[[:space:]]+)?GamaPlatformServices\b' \
  "$ROOT/Sources/GamaCore" "$ROOT/Sources/GamaPlugin" "$ROOT/Sources/GamaDraw" \
  "$ROOT/Sources/GamaMacros" "$ROOT/Sources/GamaMacrosImpl" "$ROOT/Sources/gama" \
  "$ROOT/Sources/GamaTUI" "$ROOT/Sources/GamaWASM" "$ROOT/Sources/GamaAppleUI" \
  "$ROOT/Sources/GamaAppleShell" "$ROOT/Sources/GamaEmbed" "$ROOT/Sources/GamaEmbedABI" \
  "$ROOT/Sources/GamaMLIR"; then
  echo "error: a portable/framework target imported GamaPlatformServices" >&2; exit 1
fi
# Confinement negatives: Signal is non-Sendable. These fixtures live
# outside every SwiftPM target (ADR 0009).
#   error.*  -> must FAIL to compile
#   warn.*   -> must compile but emit #UnavailableSendableConformance
# A retroactive @unchecked conformance is only a warning on the pinned
# toolchain, so the gate pins the diagnostic rather than pretending the
# conformance is impossible.
if [[ -d "$ROOT/Tests/Fixtures/Confinement" ]]; then
  swiftc_bin="${GAMA_SWIFTC_64:-$(xcrun --toolchain "${GAMA_TOOLCHAIN_ID:-org.swift.65202608211a}" --find swiftc)}"
  conf_scratch="${GAMA_CONFINEMENT_SCRATCH_PATH:-$(mktemp -d)/spm}"
  xcrun --toolchain "${GAMA_TOOLCHAIN_ID:-org.swift.65202608211a}" swift build \
    --package-path "$ROOT" --scratch-path "$conf_scratch" --target GamaCore >/dev/null
  conf_inc="$(dirname "$(find "$conf_scratch" -name 'GamaCore.swiftmodule' -print -quit)")"
  conf_n=0
  for fixture in "$ROOT"/Tests/Fixtures/Confinement/*.swift; do
    base="$(basename "$fixture")"
    out="$("$swiftc_bin" -typecheck -swift-version 6 -I "$conf_inc" "$fixture" 2>&1)" && rc=0 || rc=$?
    case "$base" in
      error.*)
        if [[ $rc -eq 0 ]]; then
          echo "error: confinement negative compiled but must not: $base" >&2; exit 1
        fi
        ;;
      warn.*)
        if [[ $rc -ne 0 ]]; then
          echo "error: confinement fixture failed to compile, expected a warning: $base" >&2; exit 1
        fi
        if ! grep -q 'UnavailableSendableConformance' <<<"$out"; then
          echo "error: expected #UnavailableSendableConformance from $base" >&2; exit 1
        fi
        ;;
    esac
    conf_n=$((conf_n + 1))
  done
  echo "OK — Signal confinement negatives ($conf_n fixtures)"
fi

grep -q 'swift-tools-version: 6.4' "$ROOT/Package.swift"
"$ROOT/scripts/check-toolchain-pins.sh"
echo "OK — portable-core and explicit-ownership boundaries"
