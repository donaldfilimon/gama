#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${GAMA_LINUX_SDK_ID:-swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-08-14-a_static-linux-0.1.0}"
SWIFT="${GAMA_SWIFT_64:-/Users/donaldfilimon/Library/Developer/Toolchains/swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-08-14-a.xctoolchain/usr/bin/swift}"
"$SWIFT" --version | grep -q 'Swift version 6.4'
"$SWIFT" sdk list | grep -Fxq "$SDK" || { echo "error: missing Linux SDK $SDK" >&2; exit 1; }
"$SWIFT" build --package-path "$ROOT" --scratch-path /private/tmp/gama-linux-swiftpm --swift-sdk "$SDK" --triple aarch64-swift-linux-musl --target GamaCore
echo "OK — Linux SDK build"
