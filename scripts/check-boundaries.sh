#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLCHAIN="${GAMA_TOOLCHAIN_ID:-org.swift.65202608211a}"
swift_bin="$(xcrun --toolchain "$TOOLCHAIN" --find swift)"
swiftc_bin="${GAMA_SWIFTC_64:-$(xcrun --toolchain "$TOOLCHAIN" --find swiftc)}"
# Catches every import spelling: plain, indented, access-scoped
# (`public import`), attributed (`@preconcurrency`, `@_implementationOnly`),
# and submodule/decl imports (`import struct Foundation.Data`). The old
# anchored `^import X$` form was blind to all but the plain spelling.
if grep -R -n -E --include='*.swift' \
  '^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*(public|package|internal|private|fileprivate)?[[:space:]]*import[[:space:]]+((struct|class|enum|protocol|typealias|func|var|let)[[:space:]]+)?(Foundation|AppKit|UIKit|Darwin|Glibc|WinSDK|Synchronization)\b' \
  "$ROOT/Sources/GamaCore" "$ROOT/Sources/GamaPlugin"; then
  echo "error: GamaCore/GamaPlugin imported a platform/runtime module" >&2; exit 1
fi
if grep -R -n -E --include='*.swift' 'ActionRegistry|Invalidator\.shared|nonisolated\(unsafe\).*_host' "$ROOT/Sources/GamaCore" "$ROOT/Sources/GamaPlugin" "$ROOT/Sources/GamaEmbed"; then
  echo "error: process-global framework state detected" >&2; exit 1
fi
# POSIX handlers must terminate at the C support boundary. A Swift handler
# closure or Swift-owned signal storage can enter runtime initialization or
# exclusivity machinery from asynchronous signal context.
if grep -n -E 'nonisolated\(unsafe\)|@convention\(c\)|sigaction\(|atexit\(' \
  "$ROOT/Sources/GamaTUI/TerminalRescue.swift"; then
  echo "error: GamaTUI signal handler state or installation escaped into Swift" >&2; exit 1
fi
grep -q 'static struct termios gama_tui_saved_termios' \
  "$ROOT/Sources/GamaTUISignal/GamaTUISignal.c"
grep -q 'static struct sigaction gama_tui_saved_actions' \
  "$ROOT/Sources/GamaTUISignal/GamaTUISignal.c"

# Saved dispositions must be fully published before the first process-wide
# handler install. Signals are blocked only on the calling thread, so another
# host thread may enter a newly installed handler immediately.
signal_source="$ROOT/Sources/GamaTUISignal/GamaTUISignal.c"
publish_line="$(grep -n 'result = gama_tui_publish_saved_actions();' "$signal_source" | cut -d: -f1)"
install_line="$(grep -n 'result = gama_tui_install_saved_handlers();' "$signal_source" | cut -d: -f1)"
[[ -n "$publish_line" && -n "$install_line" && "$publish_line" -lt "$install_line" ]] || {
  echo "error: saved signal actions must be published before handler installation" >&2
  exit 1
}
grep -q 'GAMA_TUI_INSTALL_DEFER_PUBLISHING' "$signal_source"
grep -q '__atomic_compare_exchange_n' "$signal_source"
echo "OK — TUI signal handlers and storage confined to C"

# Exercise the handler itself outside Swift: it must re-raise through the
# displaced host disposition and must not write to a potentially blocking
# terminal output descriptor on a fatal signal.
signal_probe_dir="$(mktemp -d)"
trap 'rm -rf "$signal_probe_dir"' EXIT
/usr/bin/xcrun clang -std=c11 -Wall -Wextra -Werror \
  -I "$ROOT/Sources/GamaTUISignal/include" \
  "$ROOT/Sources/GamaTUISignal/GamaTUISignal.c" \
  "$ROOT/Tests/Fixtures/TerminalSignal/TerminalSignalProbe.c" \
  -o "$signal_probe_dir/terminal-signal-probe"
"$signal_probe_dir/terminal-signal-probe"
# Inverse boundary: GamaPlatformServices (Foundation-backed service
# implementations) must never leak into a portable or framework target.
# Only demos, examples, and tests may import it.
if grep -R -n -E --include='*.swift' \
  '^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*(public|package|internal|private|fileprivate)?[[:space:]]*import[[:space:]]+((struct|class|enum|protocol|typealias|func|var|let)[[:space:]]+)?GamaPlatformServices\b' \
  "$ROOT/Sources/GamaCore" "$ROOT/Sources/GamaPlugin" "$ROOT/Sources/GamaDraw" \
  "$ROOT/Sources/GamaMacros" "$ROOT/Sources/GamaMacrosImpl" "$ROOT/Sources/gama" \
  "$ROOT/Sources/GamaTUI" "$ROOT/Sources/GamaWASM" "$ROOT/Sources/GamaAppleUI" \
  "$ROOT/Sources/GamaAppleShell" "$ROOT/Sources/GamaEmbed" "$ROOT/Sources/GamaEmbedABI" \
  "$ROOT/Sources/GamaMLIR"; then
  echo "error: a portable/framework target imported GamaPlatformServices" >&2; exit 1
fi
# Compile the platform-free targets before any cross-platform product link,
# then inspect the actual undefined references. Import greps cannot see
# compiler-emitted libm dependencies such as FloatingPoint.rounded().
portable_scratch="${GAMA_PORTABLE_SYMBOL_SCRATCH_PATH:-$(mktemp -d)/spm}"
portable_targets=(GamaCore GamaPlugin GamaDraw GamaMLIR)
for target in "${portable_targets[@]}"; do
  "$swift_bin" build --package-path "$ROOT" --scratch-path "$portable_scratch" \
    --target "$target" >/dev/null
  target_objects=()
  while IFS= read -r -d '' object; do target_objects+=("$object"); done < <(
    find "$portable_scratch" -type f \
      \( -path "*/${target}-t.build/Objects-normal/*/*.o" \
         -o -path "*/${target}.build/*.o" \) -print0
  )
  [[ ${#target_objects[@]} -gt 0 ]] || {
    echo "error: no compiled objects found for portable target $target" >&2; exit 1
  }
  "$ROOT/scripts/check-portable-symbols.sh" "$target" "${target_objects[@]}"
done

# Prove the scanner rejects the exact source construct behind the original
# native-Linux round/rint/trunc/ceil/floor link failure.
symbol_fixture="$ROOT/Tests/Fixtures/PortableSymbols/Sources/RoundedRequiresLibm/RoundedRequiresLibm.swift"
symbol_fixture_object="${GAMA_PORTABLE_SYMBOL_FIXTURE_OUTPUT:-$(mktemp -d)/RoundedRequiresLibm.o}"
"$swiftc_bin" -parse-as-library -swift-version 6 -Onone -emit-object \
  -module-name GamaPortableSymbolNegative "$symbol_fixture" -o "$symbol_fixture_object"
if fixture_output="$("$ROOT/scripts/check-portable-symbols.sh" \
  'PortableSymbols/RoundedRequiresLibm.swift' "$symbol_fixture_object" 2>&1)"; then
  echo "error: portable-symbol negative fixture passed but must fail" >&2; exit 1
fi
grep -q '_roundSlowPath' <<<"$fixture_output" || {
  echo "error: portable-symbol fixture failed without naming _roundSlowPath" >&2; exit 1
}
echo "OK — portable-symbol negative (RoundedRequiresLibm -> _roundSlowPath)"

# Confinement negatives: Signal is non-Sendable. These fixtures live
# outside every SwiftPM target (ADR 0009).
#   error.*  -> must FAIL to compile
#   warn.*   -> must compile but emit #UnavailableSendableConformance
# A retroactive @unchecked conformance is only a warning on the pinned
# toolchain, so the gate pins the diagnostic rather than pretending the
# conformance is impossible.
if [[ -d "$ROOT/Tests/Fixtures/Confinement" ]]; then
  conf_scratch="${GAMA_CONFINEMENT_SCRATCH_PATH:-$portable_scratch}"
  conf_inc="$(dirname "$(find "$conf_scratch" -name 'GamaCore.swiftmodule' -print -quit)")"
  conf_n=0
  for fixture in "$ROOT"/Tests/Fixtures/Confinement/*.swift; do
    base="$(basename "$fixture")"
    out="$("$swiftc_bin" -typecheck -swift-version 6 -I "$conf_inc" "$fixture" 2>&1)" && rc=0 || rc=$?
    case "$base" in
      error.*)
        if [[ $rc -eq 0 ]]; then
          echo "error: confinement negative compiled but must not: $base" >&2; exit 1
        fi
        ;;
      warn.*)
        if [[ $rc -ne 0 ]]; then
          echo "error: confinement fixture failed to compile, expected a warning: $base" >&2; exit 1
        fi
        if ! grep -q 'UnavailableSendableConformance' <<<"$out"; then
          echo "error: expected #UnavailableSendableConformance from $base" >&2; exit 1
        fi
        ;;
    esac
    conf_n=$((conf_n + 1))
  done
  echo "OK — Signal confinement negatives ($conf_n fixtures)"
fi

# Ownership fixtures: Terminal is ~Copyable (ADR 0010). These live outside
# every SwiftPM target, like the confinement fixtures.
#   error.*  -> must FAIL to compile, with the diagnostic its
#               `// EXPECT-DIAGNOSTIC:` line names
#   ok.*     -> must compile; this is the harness check, without which a
#               broken include path would make every negative "fail" for the
#               wrong reason and the gate would pass vacuously
#
# THE `-c` IS LOAD-BEARING AND MUST NOT BE WEAKENED TO `-typecheck`.
# Move-only enforcement runs in SIL, after type checking. Measured 2026-08-28
# on the pinned 6.5-dev snapshot and on Xcode's Swift 6.4: a plain
# use-after-consume of a noncopyable value exits 0 under `swiftc -typecheck`
# and only fails under `swiftc -c`. A `-typecheck` gate here would prove
# nothing — the same false negative this repo rejected when it removed the
# `leak:XCTest` suppression. The gate is self-protecting: reverting to
# `-typecheck` makes error.TerminalMustNotBeCopied.swift compile, which trips
# the "compiled but must not" branch below.
#
# Unlike the confinement fixtures these import GamaTUI, which imports Darwin
# and the GamaTUISignal C target — hence the explicit `-sdk` and a module map
# written here. The module map is generated rather than found inside the
# SwiftPM scratch so the gate does not couple to build-system layout.
if [[ -d "$ROOT/Tests/Fixtures/Ownership" ]]; then
  own_probe_dir="$(mktemp -d)"
  trap 'rm -rf "$signal_probe_dir" "$own_probe_dir"' EXIT
  "$swift_bin" build --package-path "$ROOT" --scratch-path "$portable_scratch" \
    --target GamaTUI >/dev/null
  # The build writes GamaTUI.swiftmodule in more than one place and `find`
  # order is not stable, so require the directory that holds *both* modules
  # the fixtures import rather than taking the first hit.
  own_inc=""
  while IFS= read -r candidate; do
    candidate_dir="$(dirname "$candidate")"
    if [[ -e "$candidate_dir/GamaCore.swiftmodule" ]]; then
      own_inc="$candidate_dir"; break
    fi
  done < <(find "$portable_scratch" -name 'GamaTUI.swiftmodule')
  [[ -n "$own_inc" && -d "$own_inc" ]] || {
    echo "error: no directory holds both GamaTUI.swiftmodule and GamaCore.swiftmodule" >&2
    exit 1
  }
  cat >"$own_probe_dir/module.modulemap" <<MODULEMAP
module GamaTUISignal {
    header "$ROOT/Sources/GamaTUISignal/include/GamaTUISignal.h"
    export *
}
MODULEMAP
  own_sdk="$(xcrun --show-sdk-path)"
  own_n=0
  for fixture in "$ROOT"/Tests/Fixtures/Ownership/*.swift; do
    base="$(basename "$fixture")"
    out="$("$swiftc_bin" -c -parse-as-library -swift-version 6 \
      -sdk "$own_sdk" -I "$own_inc" \
      -Xcc -fmodule-map-file="$own_probe_dir/module.modulemap" \
      -o /dev/null "$fixture" 2>&1)" && rc=0 || rc=$?
    case "$base" in
      error.*)
        expected="$(sed -n 's|^// EXPECT-DIAGNOSTIC: ||p' "$fixture")"
        if [[ -z "$expected" ]]; then
          echo "error: ownership negative has no // EXPECT-DIAGNOSTIC: line: $base" >&2; exit 1
        fi
        if [[ $rc -eq 0 ]]; then
          echo "error: ownership negative compiled but must not: $base" >&2; exit 1
        fi
        if ! grep -qF "$expected" <<<"$out"; then
          echo "error: $base failed without the expected diagnostic: $expected" >&2
          echo "$out" >&2
          exit 1
        fi
        ;;
      ok.*)
        if [[ $rc -ne 0 ]]; then
          echo "error: ownership positive failed to compile: $base" >&2
          echo "$out" >&2
          exit 1
        fi
        ;;
    esac
    own_n=$((own_n + 1))
  done
  echo "OK — Terminal ownership fixtures ($own_n fixtures)"
fi

grep -q 'swift-tools-version: 6.4' "$ROOT/Package.swift"
"$ROOT/scripts/check-toolchain-pins.sh"
echo "OK — portable-core and explicit-ownership boundaries"
