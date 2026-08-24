#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if rg -n '^import (Foundation|AppKit|UIKit|Darwin|Glibc|WinSDK|Synchronization)$' "$ROOT/Sources/GamaCore"; then
  echo "error: GamaCore imported a platform/runtime module" >&2; exit 1
fi
if rg -n 'ActionRegistry|Invalidator\.shared|nonisolated\(unsafe\).*_host' "$ROOT/Sources/GamaCore" "$ROOT/Sources/GamaEmbed"; then
  echo "error: process-global framework state detected" >&2; exit 1
fi
grep -q 'swift-tools-version: 6.4' "$ROOT/Package.swift"
echo "OK — portable-core and explicit-ownership boundaries"
