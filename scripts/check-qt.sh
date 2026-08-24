#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
QT_PREFIX="${QT_PREFIX:-/opt/homebrew/opt/qtbase}"
export QT_PREFIX
[[ -d "$QT_PREFIX/lib/QtCore.framework" ]] || { echo "error: QtCore.framework not found under $QT_PREFIX" >&2; exit 1; }
unset TOOLCHAINS || true
/usr/bin/xcrun --toolchain default swift test --package-path "$ROOT/Adapters/GamaQt" --scratch-path /private/tmp/gama-qt-swiftpm
echo "OK — optional Qt adapter"
