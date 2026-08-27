#!/usr/bin/env bash
# Fail when CI, check scripts, or .swift-version drift from Toolchains.toml.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOML="$ROOT/Toolchains.toml"
CI="$ROOT/.github/workflows/ci.yml"
PAGES="$ROOT/.github/workflows/pages.yml"

toml_get() {
  local section="$1" key="$2"
  awk -v section="$section" -v key="$key" '
    BEGIN { in_section = 0 }
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    /^[[:space:]]*\[/ {
      s = $0
      sub(/^[[:space:]]*\[/, "", s)
      sub(/\][[:space:]]*$/, "", s)
      in_section = (s == section)
      next
    }
    in_section {
      line = $0
      sub(/[[:space:]]*#.*$/, "", line)
      eq = index(line, "=")
      if (eq == 0) next
      k = substr(line, 1, eq - 1)
      v = substr(line, eq + 1)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", k)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
      gsub(/^"/, "", v)
      gsub(/"$/, "", v)
      if (k == key) {
        print v
        found = 1
        exit
      }
    }
    END { if (!found) exit 1 }
  ' "$TOML"
}

must_get() {
  local section="$1" key="$2" value
  if ! value="$(toml_get "$section" "$key")"; then
    echo "error: Toolchains.toml missing [$section].$key" >&2
    exit 1
  fi
  if [[ -z "$value" ]]; then
    echo "error: Toolchains.toml empty [$section].$key" >&2
    exit 1
  fi
  printf '%s' "$value"
}

must_contain() {
  local file="$1" needle="$2" label="$3"
  if ! grep -F -q -- "$needle" "$file"; then
    echo "error: $label missing in ${file#"$ROOT"/}: $needle" >&2
    exit 1
  fi
}

must_equal() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" != "$expected" ]]; then
    echo "error: $label mismatch" >&2
    echo "  expected: $expected" >&2
    echo "  actual:   $actual" >&2
    exit 1
  fi
}

selector="$(must_get snapshot selector)"
xctoolchain="$(must_get snapshot xctoolchain)"
xctoolchain_id="$(must_get snapshot xctoolchain_id)"
swift_revision="$(must_get snapshot swift_revision)"
swiftc_sha256="$(must_get snapshot swiftc_sha256)"
macos_url="$(must_get snapshot.macos url)"
macos_sha="$(must_get snapshot.macos sha256)"
linux_url="$(must_get snapshot.linux_x86_64 url)"
linux_sha="$(must_get snapshot.linux_x86_64 sha256)"
linux_sdk_id="$(must_get sdk.static_linux id)"
linux_sdk_url="$(must_get sdk.static_linux url)"
linux_sdk_sha="$(must_get sdk.static_linux sha256)"
wasm_sdk_id="$(must_get sdk.wasm id)"
wasm_sdk_url="$(must_get sdk.wasm url)"
wasm_sdk_sha="$(must_get sdk.wasm sha256)"
android_sdk_id="$(must_get sdk.android id)"
android_sdk_url="$(must_get sdk.android url)"
android_sdk_sha="$(must_get sdk.android sha256)"
windows_url="$(must_get windows_exception url)"
windows_sha="$(must_get windows_exception sha256)"
windows_revision="$(must_get windows_exception swift_revision)"

swift_version="$(<"$ROOT/.swift-version")"
swift_version="${swift_version%%$'\n'}"
must_equal ".swift-version" "$selector" "$swift_version"

must_contain "$CI" "$macos_url" "macOS toolchain URL"
must_contain "$CI" "$macos_sha" "macOS toolchain SHA-256"
must_contain "$CI" "$linux_url" "Linux toolchain URL"
must_contain "$CI" "$linux_sha" "Linux toolchain SHA-256"
must_contain "$CI" "$linux_sdk_id" "static Linux SDK id"
must_contain "$CI" "$linux_sdk_url" "static Linux SDK URL"
must_contain "$CI" "$linux_sdk_sha" "static Linux SDK SHA-256"
must_contain "$CI" "$wasm_sdk_id" "WASM SDK id"
must_contain "$CI" "$wasm_sdk_url" "WASM SDK URL"
must_contain "$CI" "$wasm_sdk_sha" "WASM SDK SHA-256"
must_contain "$CI" "$android_sdk_id" "Android SDK id"
must_contain "$CI" "$android_sdk_url" "Android SDK URL"
must_contain "$CI" "$android_sdk_sha" "Android SDK SHA-256"
must_contain "$CI" "$xctoolchain_id" "xctoolchain id"
must_contain "$CI" "Swift $swift_revision" "Swift 6.5-dev revision grep"
must_contain "$CI" "$windows_url" "Windows toolchain URL"
must_contain "$CI" "$windows_sha" "Windows toolchain SHA-256"
must_contain "$CI" "Swift $windows_revision" "Windows Swift revision grep"

# Pages independently builds the deployable WASM site, so its compiler and
# SDK pins must drift-fail alongside the primary acceptance workflow.
must_contain "$PAGES" "$linux_url" "Pages Linux toolchain URL"
must_contain "$PAGES" "$linux_sha" "Pages Linux toolchain SHA-256"
must_contain "$PAGES" "$wasm_sdk_id" "Pages WASM SDK id"
must_contain "$PAGES" "$wasm_sdk_url" "Pages WASM SDK URL"
must_contain "$PAGES" "$wasm_sdk_sha" "Pages WASM SDK SHA-256"

must_contain "$ROOT/scripts/ci-install-swift-snapshot.sh" \
  "Swift $swift_revision" "Swift 6.5-dev revision grep"
must_contain "$ROOT/scripts/check-embedded.sh" \
  "Swift $swift_revision" "Swift 6.5-dev revision grep"
must_contain "$ROOT/scripts/check-embedded.sh" \
  "$swiftc_sha256" "macOS swiftc SHA-256 default"
must_contain "$ROOT/scripts/check-embedded.sh" \
  "$xctoolchain" "embedded toolchain directory default"
for script in bundle-macos.sh bundle-web.sh; do
  must_contain "$ROOT/scripts/$script" \
    "Swift $swift_revision" "packaging Swift 6.5-dev revision grep"
done

for script in check-apple.sh check-docs.sh check-c-abi.sh check-mlir.sh; do
  must_contain "$ROOT/scripts/$script" "$xctoolchain_id" "GAMA_TOOLCHAIN_ID default"
done

must_contain "$ROOT/scripts/check-wasm.sh" "$wasm_sdk_id" "WASM SDK id default"
must_contain "$ROOT/scripts/check-linux.sh" "$linux_sdk_id" "static Linux SDK id default"
must_contain "$ROOT/scripts/check-android.sh" "$android_sdk_id" "Android SDK id default"

for script in check-wasm.sh check-linux.sh check-android.sh; do
  must_contain "$ROOT/scripts/$script" "$xctoolchain" "local snapshot toolchain path default"
done

echo "OK — Toolchains.toml pins match CI, check scripts, and .swift-version"
