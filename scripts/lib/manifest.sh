# Flat-TOML-subset reader for Distribution/ manifests. Recognizes blank
# lines, full-line # comments, [section] headers, and key = "value" pairs —
# nothing else. Any other line fails the whole read, which is the guard that
# keeps the manifest identity/branding-only instead of a second build system.
# Usage: manifest_get <file> <section> <key>
manifest_get() {
  local file="$1" section="$2" key="$3" current="" line value="" found=0
  local section_re='^\[([A-Za-z0-9_]+)\]$'
  local assignment_re='^([A-Za-z0-9_]+)[[:space:]]*=[[:space:]]*"([^"]*)"$'
  [[ -f "$file" ]] || { echo "error: manifest $file not found" >&2; return 1; }
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      ''|'#'*) ;;
      *)
        if [[ "$line" =~ $section_re ]]; then
          current="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ $assignment_re ]]; then
          if [[ "$current" == "$section" && "${BASH_REMATCH[1]}" == "$key" ]]; then
            value="${BASH_REMATCH[2]}"
            found=1
          fi
        else
          echo "error: unrecognized manifest line in $file: $line" >&2
          return 1
        fi ;;
    esac
  done < "$file"
  [[ "$found" == 1 ]] || { echo "error: missing [$section] $key in $file" >&2; return 1; }
  printf '%s\n' "$value"
}
