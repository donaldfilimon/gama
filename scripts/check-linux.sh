#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${GAMA_LINUX_SDK_ID:-swift-DEVELOPMENT-SNAPSHOT-2026-08-21-a_static-linux-0.1.0}"
SWIFT="${GAMA_SWIFT_64:-/Users/donaldfilimon/Library/Developer/Toolchains/swift-DEVELOPMENT-SNAPSHOT-2026-08-21-a.xctoolchain/usr/bin/swift}"
SCRATCH_ROOT="${GAMA_SCRATCH_ROOT:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}}"
"$SWIFT" --version | grep -q 'Swift version 6.5'
"$SWIFT" sdk list | grep -Fxq "$SDK" || { echo "error: missing Linux SDK $SDK" >&2; exit 1; }
"$SWIFT" build --package-path "$ROOT" --scratch-path "$SCRATCH_ROOT/gama-linux-swiftpm" --swift-sdk "$SDK" --triple aarch64-swift-linux-musl --target GamaCore
echo "OK — Linux SDK build"
