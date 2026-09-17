#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <target-label> <object>..." >&2
  exit 64
fi

target="$1"
shift
nm_bin="${GAMA_LLVM_NM:-}"
if [[ -z "$nm_bin" ]]; then
  swiftc_bin="${GAMA_SWIFTC_64:-$(xcrun --toolchain "${GAMA_TOOLCHAIN_ID:-org.swift.65202608211a}" --find swiftc)}"
  nm_bin="$(dirname "$swiftc_bin")/llvm-nm"
fi
[[ -x "$nm_bin" ]] || { echo "error: llvm-nm not found: $nm_bin" >&2; exit 1; }

# These are C math-library entry points that a compiler may emit even when
# portable Swift source imports only the standard library. The Swift
# `_roundSlowPath` reference is the host-debug precursor produced by
# FloatingPoint.rounded(); on native Linux that path has lowered to several
# of the C symbols below before the final static link.
is_forbidden_symbol() {
  [[ "$1" =~ ^(acos|acosh|asin|asinh|atan|atan2|atanh|cbrt|ceil|copysign|cos|cosh|erf|erfc|exp|exp2|expm1|fabs|fdim|floor|fma|fmax|fmin|fmod|frexp|hypot|ilogb|ldexp|lgamma|llrint|llround|log|log10|log1p|log2|logb|lrint|lround|modf|nan|nearbyint|nextafter|nexttoward|pow|remainder|remquo|rint|round|scalbln|scalbn|sin|sinh|sqrt|tan|tanh|tgamma|trunc)(f|l)?$ ]]
}

violations=0
for object in "$@"; do
  [[ -f "$object" ]] || { echo "error: object not found for $target: $object" >&2; exit 1; }
  if ! nm_output="$("$nm_bin" --undefined-only --format=posix "$object" 2>&1)"; then
    echo "error: unable to inspect $target object with llvm-nm: $object" >&2
    echo "$nm_output" >&2
    exit 1
  fi
  while IFS=' ' read -r symbol _; do
    [[ -n "$symbol" ]] || continue
    normalized="${symbol%%@*}"
    while [[ "$normalized" == _* ]]; do normalized="${normalized#_}"; done
    if is_forbidden_symbol "$normalized" || [[ "$symbol" == *'_roundSlowPath'* ]]; then
      echo "error: forbidden portable math reference '$symbol' in $target: $object" >&2
      violations=$((violations + 1))
    fi
  done <<<"$nm_output"
done

if [[ $violations -ne 0 ]]; then
  echo "error: $target has $violations libm-dependent symbol reference(s)" >&2
  exit 1
fi

echo "OK — $target has no libm-dependent symbol references ($# objects)"
