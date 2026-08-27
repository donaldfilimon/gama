#!/usr/bin/env bash
# Developer ID release path for the macOS demo app: re-signs the staged
# bundle with a real identity plus the hardened runtime, zips it, submits to
# Apple notarization, staples the ticket, and validates the staple.
#
# HARD CREDENTIAL GATE: GAMA_CODESIGN_IDENTITY (a "Developer ID Application:
# …" identity present in the keychain) and GAMA_NOTARY_PROFILE (a profile
# stored via `xcrun notarytool store-credentials`) are required. When either
# is absent this script reports credential-gated status and exits nonzero —
# it never fakes green and never falls back to ad-hoc signing (that is
# scripts/bundle-macos.sh's job).
set -euo pipefail
unset TOOLCHAINS || true
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/manifest.sh
source "$ROOT/scripts/lib/manifest.sh"
DIST="${GAMA_DIST_ROOT:-/private/tmp/gama-dist}"

missing=()
[[ -n "${GAMA_CODESIGN_IDENTITY:-}" ]] || missing+=(GAMA_CODESIGN_IDENTITY)
[[ -n "${GAMA_NOTARY_PROFILE:-}" ]] || missing+=(GAMA_NOTARY_PROFILE)
if ((${#missing[@]} > 0)); then
  echo "error: release-macos.sh is credential-gated, not broken." >&2
  echo "missing: ${missing[*]}" >&2
  echo "Set GAMA_CODESIGN_IDENTITY to a Developer ID Application identity in the keychain and" >&2
  echo "GAMA_NOTARY_PROFILE to a notarytool keychain profile (xcrun notarytool store-credentials)." >&2
  echo "The ad-hoc local bundle path (scripts/bundle-macos.sh) needs no credentials." >&2
  exit 1
fi

# Stage and fully verify the ad-hoc bundle first: the release path re-signs
# a bundle that already passed plutil, deep-strict verify, and the launch
# smoke, so a notarization failure can only be a signing/credential problem.
"$ROOT/scripts/bundle-macos.sh"

NAME="$(manifest_get "$ROOT/Distribution/gama-apple-demo.toml" app name)"
APP="$DIST/$NAME.app"
ZIP="$DIST/$NAME.zip"
[[ -d "$APP" ]] || { echo "error: staged bundle missing at $APP" >&2; exit 1; }

codesign --force --deep --options runtime --timestamp \
  -s "$GAMA_CODESIGN_IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"

rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$GAMA_NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "OK — $APP Developer ID signed, notarized, and stapled"
