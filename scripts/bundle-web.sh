#!/usr/bin/env bash
# Assembles the deployable wasm site: WebHost/index.html + WebHost/gama.js +
# gama-web-demo.wasm in one directory, then verifies the assembled directory
# with the headless-Chrome browser smoke. Build invocation matches
# scripts/check-wasm.sh (same pinned toolchain, SDK, and export list).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/manifest.sh
source "$ROOT/scripts/lib/manifest.sh"
SDK="${GAMA_WASM_SDK_ID:-swift-DEVELOPMENT-SNAPSHOT-2026-08-21-a_wasm}"
SWIFT="${GAMA_SWIFT_64:-/Users/donaldfilimon/Library/Developer/Toolchains/swift-DEVELOPMENT-SNAPSHOT-2026-08-21-a.xctoolchain/usr/bin/swift}"
SCRATCH_ROOT="${GAMA_SCRATCH_ROOT:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}}"
SCRATCH="$SCRATCH_ROOT/gama-web-bundle-swiftpm"
DIST="${GAMA_DIST_ROOT:-/private/tmp/gama-dist}"

# Manifest identity (fail-closed parse; branding only, never build facts).
APP_ID="$(manifest_get "$ROOT/Distribution/gama-web-demo.toml" app id)"
APP_VERSION="$(manifest_get "$ROOT/Distribution/gama-web-demo.toml" app version)"
WEB_TITLE="$(manifest_get "$ROOT/Distribution/gama-web-demo.toml" web title)"

# Prerequisites fail closed with explicit messages: an absent pinned
# toolchain or WASM SDK is a missing prerequisite, not a product failure.
[[ -x "$SWIFT" ]] || {
  echo "error: pinned Swift toolchain not found at $SWIFT" >&2
  echo "prerequisite-gated, not broken: install the pinned snapshot (Toolchains.toml) or set GAMA_SWIFT_64" >&2
  exit 1
}
version="$("$SWIFT" --version)"
grep -q 'Swift version 6.5' <<<"$version" &&
  grep -q 'Swift 95c5142e84b82c1' <<<"$version" || {
  echo "error: web bundle gate requires the pinned Swift 6.5-dev snapshot" >&2
  echo "$version" >&2
  exit 1
}
"$SWIFT" sdk list | grep -Fxq "$SDK" || {
  echo "error: missing WASM SDK $SDK" >&2
  echo "prerequisite-gated, not broken: install the pinned SDK (Toolchains.toml) or run this gate in the wasm CI job" >&2
  exit 1
}

"$SWIFT" build --package-path "$ROOT" --scratch-path "$SCRATCH" --swift-sdk "$SDK" --product gama-web-demo \
  -Xlinker --export=gama_web_v1_frame \
  -Xlinker --export=gama_web_v1_key \
  -Xlinker --export=gama_web_v1_pointer \
  -Xlinker --export=gama_web_v1_resize
artifact="$(find "$SCRATCH" -type f -name 'gama-web-demo.wasm' -print -quit)"
[[ -n "$artifact" ]] || { echo "error: executable WASM artifact not produced" >&2; exit 1; }

mkdir -p "$DIST/web"
command cp -f "$ROOT/WebHost/index.html" "$ROOT/WebHost/gama.js" "$DIST/web/"
command cp -f "$artifact" "$DIST/web/gama-web-demo.wasm"
node "$ROOT/scripts/set-web-title.mjs" "$DIST/web/index.html" "$WEB_TITLE"

# The site claim is only real when the assembled directory itself passes the
# browser smoke (DOM, keyboard, pointer, resize, rAF, accessibility, frames).
node "$ROOT/scripts/browser-runtime-smoke.mjs" \
  "$DIST/web/gama-web-demo.wasm" "$DIST/web" "$WEB_TITLE"

echo "OK — wasm site $APP_ID $APP_VERSION assembled at $DIST/web and browser-smoke verified"
