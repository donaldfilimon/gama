#!/usr/bin/env bash
# Shared toolchain resolution for the gate and packaging scripts.
#
# Toolchains.toml is the pin authority. Deriving the installed snapshot's
# path from it, rather than writing one out, keeps a single source of truth
# and keeps a developer's home directory out of scripts that are checked in:
# a hardcoded /Users/<name> default is correct on exactly one machine and
# silently wrong on every other, inside gates that are supposed to fail
# closed. CI never reached those defaults, because
# ci-install-swift-snapshot.sh exports GAMA_SWIFT_64 and GAMA_SWIFTC_64, so
# this is a portability fix rather than a CI fix.
#
# Every function honors an explicit override, so callers keep the same
# `${GAMA_SWIFT_64:-<default>}` shape they had before.

# Repository root. Gate scripts already compute ROOT before sourcing this
# file, so prefer theirs; fall back to this file's location. Resolving to the
# wrong root silently yields the wrong toolchain, so every caller below treats
# a failed read as fatal rather than defaulting.
gama_lib_root() {
  if [[ -n "${ROOT:-}" && -f "${ROOT}/Toolchains.toml" ]]; then
    printf '%s' "$ROOT"
    return 0
  fi
  local here
  here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
  printf '%s' "$(dirname "$here")"
}

# gama_toml_get <section> <key> — read one value from Toolchains.toml.
# Accepts blank lines, # comments, [section] headers, and key = "value".
gama_toml_get() {
  local section="$1" key="$2" root
  root="$(gama_lib_root)"
  if [[ ! -f "$root/Toolchains.toml" ]]; then
    echo "error: Toolchains.toml not found under $root" >&2
    return 1
  fi
  awk -v section="$section" -v key="$key" '
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
      gsub(/^"/, "", v); gsub(/"$/, "", v)
      if (k == key) { print v; found = 1; exit }
    }
    END { if (!found) exit 1 }
  ' "$root/Toolchains.toml"
}

# Directory of the pinned snapshot toolchain for the current user.
gama_snapshot_toolchain_dir() {
  local name
  name="$(gama_toml_get snapshot xctoolchain)" || {
    echo "error: Toolchains.toml missing [snapshot].xctoolchain" >&2
    return 1
  }
  printf '%s/Library/Developer/Toolchains/%s' "${HOME:?HOME is required}" "$name"
}

# Absolute path to the pinned snapshot's `swift` / `swiftc`.
# These propagate failure rather than printing a path built from an empty
# directory: `/usr/bin/swift` is a real binary and the wrong compiler, so a
# silent fallback would defeat the pin these gates exist to enforce.
gama_snapshot_swift() {
  local dir
  dir="$(gama_snapshot_toolchain_dir)" || return 1
  printf '%s/usr/bin/swift' "$dir"
}

gama_snapshot_swiftc() {
  local dir
  dir="$(gama_snapshot_toolchain_dir)" || return 1
  printf '%s/usr/bin/swiftc' "$dir"
}
