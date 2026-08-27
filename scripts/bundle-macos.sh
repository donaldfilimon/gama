#!/usr/bin/env bash
# Stages, ad-hoc signs, and verifies the macOS demo app bundle. The .app is
# assembled under $GAMA_DIST_ROOT (default /private/tmp/gama-dist) and NEVER
# inside the repo tree: the canonical checkout is iCloud/FileProvider-managed
# and codesign rejects bundles staged there ("resource fork, Finder
# information, or similar detritus not allowed" — measured, see CLAUDE.md).
# Ad-hoc signed apps run on the building machine only; Gatekeeper blocks them
# elsewhere. Distribution signing lives in scripts/release-macos.sh.
set -euo pipefail
unset TOOLCHAINS || true
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/manifest.sh
source "$ROOT/scripts/lib/manifest.sh"
SCRATCH="${GAMA_MACOS_BUNDLE_SCRATCH_PATH:-/private/tmp/gama-macos-bundle-swiftpm}"
DIST="${GAMA_DIST_ROOT:-/private/tmp/gama-dist}"
SWIFT=(/usr/bin/xcrun --toolchain "${GAMA_TOOLCHAIN_ID:-org.swift.65202608211a}" swift)
EXECUTABLE="gama-apple-demo"
MANIFEST="$ROOT/Distribution/gama-apple-demo.toml"

version="$("${SWIFT[@]}" --version)"
grep -q 'Swift version 6.5' <<<"$version" &&
  grep -q 'Swift 95c5142e84b82c1' <<<"$version" || {
  echo "error: macOS bundle gate requires the pinned Swift 6.5-dev snapshot" >&2
  echo "$version" >&2
  exit 1
}

# Resolve relative paths, `..`, and symlinks before any bundle is removed or
# staged. Creating the output root itself is harmless; the containment check
# still runs before a signed artifact or other content is written there.
case "$DIST" in
  /*) ;;
  *) DIST="$PWD/$DIST" ;;
esac
case "$DIST" in
  "$ROOT"|"$ROOT"/*)
    echo "error: GAMA_DIST_ROOT ($DIST) is inside the repo tree; codesigned bundles must stage outside iCloud" >&2
    exit 1 ;;
esac
mkdir -p "$DIST"
DIST="$(cd "$DIST" && pwd -P)"

case "$DIST" in
  "$ROOT"|"$ROOT"/*)
    echo "error: GAMA_DIST_ROOT ($DIST) is inside the repo tree; codesigned bundles must stage outside iCloud" >&2
    exit 1 ;;
esac

# Identity comes from the manifest (fail-closed parse); build facts do not.
BUNDLE_ID="$(manifest_get "$MANIFEST" app id)"
NAME="$(manifest_get "$MANIFEST" app name)"
APP_VERSION="$(manifest_get "$MANIFEST" app version)"
MINIMUM_SYSTEM="$(manifest_get "$MANIFEST" macos minimum_system)"
CATEGORY="$(manifest_get "$MANIFEST" macos category)"
[[ -n "$NAME" && "$NAME" != */* && "$NAME" != '.' && "$NAME" != '..' ]] || {
  echo "error: manifest app name must be a non-path bundle name" >&2
  exit 1
}

"${SWIFT[@]}" build -c release --package-path "$ROOT" --scratch-path "$SCRATCH" --product "$EXECUTABLE"
BIN_DIR="$("${SWIFT[@]}" build -c release --package-path "$ROOT" --scratch-path "$SCRATCH" --product "$EXECUTABLE" --show-bin-path | tail -1)"
[[ -x "$BIN_DIR/$EXECUTABLE" ]] || { echo "error: release build produced no $EXECUTABLE" >&2; exit 1; }

APP="$DIST/$NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
PLIST="$APP/Contents/Info.plist"
command cp -f "$ROOT/Distribution/macos/Info.plist.in" "$PLIST"
plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$PLIST"
plutil -replace CFBundleName -string "$NAME" "$PLIST"
plutil -replace CFBundleDisplayName -string "$NAME" "$PLIST"
plutil -replace CFBundleShortVersionString -string "$APP_VERSION" "$PLIST"
plutil -replace CFBundleVersion -string "$APP_VERSION" "$PLIST"
plutil -replace LSMinimumSystemVersion -string "$MINIMUM_SYSTEM" "$PLIST"
plutil -replace LSApplicationCategoryType -string "$CATEGORY" "$PLIST"
plutil -replace CFBundleExecutable -string "$EXECUTABLE" "$PLIST"
printf 'APPL????' > "$APP/Contents/PkgInfo"
command cp -f "$BIN_DIR/$EXECUTABLE" "$APP/Contents/MacOS/$EXECUTABLE"

# Icon: built from Distribution/macos/icon.png when present; a missing icon
# source is a notice, not a failure (the bundle ships icon-less).
ICON_SOURCE="$ROOT/Distribution/macos/icon.png"
if [[ -f "$ICON_SOURCE" ]]; then
  ICONSET="$DIST/gama-macos-iconset.iconset"
  rm -rf "$ICONSET"
  mkdir -p "$ICONSET"
  for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
  plutil -insert CFBundleIconFile -string AppIcon "$PLIST"
  rm -rf "$ICONSET"
else
  echo "notice: no Distribution/macos/icon.png — staging the bundle without an .icns"
fi

# Verification gates; all must pass for the bundle claim to be real.
plutil -lint "$PLIST"
codesign --force -s - "$APP"
codesign --verify --deep --strict "$APP"
"$APP/Contents/MacOS/$EXECUTABLE" --smoke

echo "OK — $APP staged ($BUNDLE_ID $APP_VERSION), ad-hoc signed, deep-strict verified, launch smoke green"
echo "note: ad-hoc signature runs on this machine only; use scripts/release-macos.sh for Developer ID + notarization"
