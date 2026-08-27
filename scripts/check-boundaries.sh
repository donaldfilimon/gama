#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Catches every import spelling: plain, indented, access-scoped
# (`public import`), attributed (`@preconcurrency`, `@_implementationOnly`),
# and submodule/decl imports (`import struct Foundation.Data`). The old
# anchored `^import X$` form was blind to all but the plain spelling.
if grep -R -n -E --include='*.swift' \
  '^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*(public|package|internal|private|fileprivate)?[[:space:]]*import[[:space:]]+((struct|class|enum|protocol|typealias|func|var|let)[[:space:]]+)?(Foundation|AppKit|UIKit|Darwin|Glibc|WinSDK|Synchronization)\b' \
  "$ROOT/Sources/GamaCore"; then
  echo "error: GamaCore imported a platform/runtime module" >&2; exit 1
fi
if grep -R -n -E --include='*.swift' 'ActionRegistry|Invalidator\.shared|nonisolated\(unsafe\).*_host' "$ROOT/Sources/GamaCore" "$ROOT/Sources/GamaEmbed"; then
  echo "error: process-global framework state detected" >&2; exit 1
fi
grep -q 'swift-tools-version: 6.4' "$ROOT/Package.swift"
"$ROOT/scripts/check-toolchain-pins.sh"
echo "OK — portable-core and explicit-ownership boundaries"
