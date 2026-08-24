#!/usr/bin/env bash
set -euo pipefail

: "${GAMA_SWIFT_64_URL:?exact Swift 6.4 snapshot URL is required}"
: "${GAMA_SWIFT_64_SHA256:?exact Swift 6.4 snapshot SHA-256 is required}"

archive="${RUNNER_TEMP:-/private/tmp}/gama-swift-6.4.tar.gz"
install_root="${RUNNER_TEMP:-/private/tmp}/gama-swift-6.4"
curl --fail --location --retry 3 "$GAMA_SWIFT_64_URL" --output "$archive"
printf '%s  %s\n' "$GAMA_SWIFT_64_SHA256" "$archive" | sha256sum --check --strict
mkdir -p "$install_root"
tar -xzf "$archive" --strip-components=1 -C "$install_root"

swift_bin="$(find "$install_root" -type f -path '*/usr/bin/swift' -print -quit)"
test -n "$swift_bin"
swift_dir="$(dirname "$swift_bin")"
echo "$swift_dir" >> "${GITHUB_PATH:?GITHUB_PATH is required}"
echo "GAMA_SWIFT_64=$swift_bin" >> "${GITHUB_ENV:?GITHUB_ENV is required}"
echo "GAMA_SWIFTC_64=$swift_dir/swiftc" >> "$GITHUB_ENV"
"$swift_bin" --version | tee swift-version.txt
grep -q 'Swift version 6.4' swift-version.txt
grep -q 'Swift 424cae54c1a10da' swift-version.txt
