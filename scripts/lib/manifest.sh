# Flat-TOML-subset reader for Distribution/ manifests. Recognizes blank
# lines, full-line # comments, [section] headers, and key = "value" pairs —
# nothing else. Any other line fails the whole read, which is the guard that
# keeps the manifest identity/branding-only instead of a second build system.
# Usage: manifest_get <file> <section> <key>
manifest_get() {
  local file="$1" section="$2" key="$3" current="" line value="" found=0
  [[ -f "$file" ]] || { echo "error: manifest $file not found" >&2; return 1; }
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      ''|'#'*) ;;
      '['*']') current="${line#\[}"; current="${current%\]}" ;;
      [A-Za-z0-9_]*' = "'*'"')
        if [[ "$current" == "$section" && "${line%% = *}" == "$key" ]]; then
          value="${line#* = \"}"; value="${value%\"}"; found=1
        fi ;;
      *) echo "error: unrecognized manifest line in $file: $line" >&2; return 1 ;;
    esac
  done < "$file"
  [[ "$found" == 1 ]] || { echo "error: missing [$section] $key in $file" >&2; return 1; }
  printf '%s\n' "$value"
}
