#!/usr/bin/env bash
set -euo pipefail

: "${GAMA_SWIFT_64:?path to the exact Swift 6.4 executable is required}"
: "${GAMA_SWIFT_SDK_URL:?exact Swift SDK URL is required}"
: "${GAMA_SWIFT_SDK_SHA256:?exact Swift SDK SHA-256 is required}"
: "${GAMA_SWIFT_SDK_ID:?exact Swift SDK ID is required}"

if ! "$GAMA_SWIFT_64" sdk list | grep -Fxq "$GAMA_SWIFT_SDK_ID"; then
  "$GAMA_SWIFT_64" sdk install "$GAMA_SWIFT_SDK_URL" --checksum "$GAMA_SWIFT_SDK_SHA256"
fi
"$GAMA_SWIFT_64" sdk list | grep -Fxq "$GAMA_SWIFT_SDK_ID"
