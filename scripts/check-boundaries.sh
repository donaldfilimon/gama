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
grep -q 'swift-tools-version: 6.4' "$ROOT/Package.swift"
"$ROOT/scripts/check-toolchain-pins.sh"
echo "OK — portable-core and explicit-ownership boundaries"
