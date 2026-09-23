#!/usr/bin/env bash
# The gate. Prints "check.sh: PASSED" only after every step succeeds.
# Run as: ./tools/check.sh >| check.log 2>&1; echo "EXIT:$?"
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
unset TOOLCHAINS

# Minimum test count. A filter or a target that silently matches nothing
# prints success with zero tests, so the gate asserts a floor. Raise it when
# tests are added; never lower it to make the gate pass.
MIN_TESTS=273
# Standard-library-only targets (ADR 0001, ADR 0005, ADR 0006, ADR 0007).
LIBRARIES=("Sources/GamaAuthoring" "Sources/GamaUSD" "Sources/GamaConsole" "Sources/GamaGraph")
BANNED='Foundation|Darwin|Glibc|simd|RealityKit|SwiftUI|AppKit|UIKit|Combine|Dispatch'

echo "==> toolchain"
version="$(swiftly run swift --version 2>&1)"
grep -q 'Swift version 6.5-dev' <<<"$version" || {
  echo "error: expected the pinned 6.5-dev snapshot, got: $version" >&2; exit 1; }

for LIBRARY in "${LIBRARIES[@]}"; do
echo "==> portable-import ban ($LIBRARY)"
# Fail closed: BSD grep over a missing path exits 1 with no output, which
# would read as "no violation".
[[ -d "$LIBRARY" ]] || { echo "error: $LIBRARY is missing" >&2; exit 1; }
sources=()
while IFS= read -r file; do sources+=("$file"); done < <(find "$LIBRARY" -name '*.swift' | sort)
[[ ${#sources[@]} -gt 0 ]] || { echo "error: no Swift sources under $LIBRARY" >&2; exit 1; }
# grep exits 0 on a match, 1 on none, and 2 or more on its own failure; only
# exit 1 is a clean result, so the code is captured rather than tested in `if`.
set +e
hits="$(grep -n -E "^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*((public|package|internal|fileprivate|private)[[:space:]]+)?import[[:space:]]+(struct[[:space:]]+|class[[:space:]]+|enum[[:space:]]+|func[[:space:]]+|protocol[[:space:]]+)?($BANNED)\b" "${sources[@]}")"
rc=$?
set -e
case $rc in
  0) echo "$hits" >&2
     echo "error: $LIBRARY must stay standard-library-only (ADR 0001)" >&2; exit 1 ;;
  1) ;;
  *) echo "error: import scan failed (grep exit $rc)" >&2; exit 1 ;;
esac
done

echo "==> build (warnings as errors)"
swiftly run swift build -Xswiftc -warnings-as-errors

echo "==> test"
log="$(mktemp -t gama-studio-test)"
trap 'rm -f "$log"' EXIT
set +e
swiftly run swift test >"$log" 2>&1 </dev/null
status=$?
set -e
cat "$log"
[[ $status -eq 0 ]] || { echo "error: swift test exited $status" >&2; exit 1; }
# Swift Testing prints one summary per test target; every one must pass and
# the floor applies to their sum.
plain="$(sed 's/\x1b\[[0-9;]*m//g' "$log")"
if grep -E 'Test run with [0-9]+ tests? .* failed' <<<"$plain"; then
  echo "error: a Swift Testing run failed" >&2; exit 1
fi
summaries="$(grep -E 'Test run with [0-9]+ tests? .* passed' <<<"$plain" || true)"
[[ -n "$summaries" ]] || { echo "error: no passing Swift Testing summary in the log" >&2; exit 1; }
count=0
while IFS= read -r line; do
  count=$(( count + $(sed -E 's/.*Test run with ([0-9]+) tests?.*/\1/' <<<"$line") ))
done <<<"$summaries"
(( count >= MIN_TESTS )) || { echo "error: ran $count tests, expected at least $MIN_TESTS" >&2; exit 1; }
echo "tests: $count (floor $MIN_TESTS)"

echo "==> smoke"
# Launches the real executable headless: one frame, the RealityKit viewport
# attached to its native region, and the sample scene projected. The exit
# code is checked directly, never through a pipe.
set +e
swiftly run swift run gama-studio --smoke </dev/null
status=$?
set -e
[[ $status -eq 0 ]] || { echo "error: gama-studio --smoke exited $status" >&2; exit 1; }

echo "==> usd"
# Writes the sample scene headlessly, validates it with Apple's USD tools,
# lets usdcat reformat it, then reads that back and re-exports: the writer is
# deterministic, so byte equality of the two exports means the reformatted
# file described the same document. Fails closed without the tools.
for tool in usdchecker usdcat; do
  command -v "$tool" >/dev/null || { echo "error: $tool is required for the usd stage (Apple USD Tools)" >&2; exit 1; }
done
usd_dir="$(mktemp -d -t gama-studio-usd)"
trap 'rm -f "$log"; rm -rf "$usd_dir"' EXIT
swiftly run swift run gama-studio --export "$usd_dir/sample.usda" </dev/null
checker="$(usdchecker "$usd_dir/sample.usda" 2>&1)" || { echo "$checker" >&2; echo "error: usdchecker rejected the export" >&2; exit 1; }
grep -q 'Success!' <<<"$checker" || { echo "$checker" >&2; echo "error: usdchecker did not report Success!" >&2; exit 1; }
# The goldens cover what the sample cannot: nested gprims, a light first
# root with materials, component children, and awkward names.
goldens=(Tests/GamaUSDTests/Fixtures/*.usda)
[[ -e "${goldens[0]}" ]] || { echo "error: no USDA goldens under Tests/GamaUSDTests/Fixtures" >&2; exit 1; }
for golden in "${goldens[@]}"; do
  checker="$(usdchecker "$golden" 2>&1)" || { echo "$checker" >&2; echo "error: usdchecker rejected $golden" >&2; exit 1; }
  grep -q 'Success!' <<<"$checker" || { echo "$checker" >&2; echo "error: usdchecker did not report Success! for $golden" >&2; exit 1; }
done
usdcat "$usd_dir/sample.usda" -o "$usd_dir/reformatted.usda"
swiftly run swift run gama-studio --open "$usd_dir/reformatted.usda" --export "$usd_dir/again.usda" </dev/null
cmp "$usd_dir/sample.usda" "$usd_dir/again.usda" || { echo "error: usdcat round trip changed the document" >&2; exit 1; }
echo "usd: usdchecker Success! (sample + ${#goldens[@]} goldens), usdcat round trip identical"

echo "==> ios and visionos (ADR 0008, ADR 0010-0014)"
# Builds the editor library and the app for both simulators with Xcode's
# toolchain, then launches the app with --smoke on one simulator of each
# platform and requires its OK line. Fails closed without Xcode, the
# simulators, or a successful launch. Device names are overridable.
for tool in xcodebuild xcrun; do
  command -v "$tool" >/dev/null || { echo "error: $tool is required for the ios/visionos stage" >&2; exit 1; }
done
apple_dd="${GAMA_STUDIO_APPLE_DERIVED_DATA:-${TMPDIR:-/tmp}/gama-studio-apple-dd}"
apple_log="$(mktemp -t gama-studio-apple)"
trap 'rm -f "$log" "$apple_log"; rm -rf "$usd_dir"' EXIT
for platform in "iOS Simulator" "visionOS Simulator"; do
  for build in "-scheme GamaStudioEditor" "-project Apps/GamaStudioApp/GamaStudioApp.xcodeproj -scheme GamaStudio"; do
    set +e
    # shellcheck disable=SC2086
    env -u TOOLCHAINS xcodebuild $build -destination "generic/platform=$platform" \
      -derivedDataPath "$apple_dd" build </dev/null >"$apple_log" 2>&1
    status=$?
    set -e
    if [[ $status -ne 0 ]] || ! grep -q '\*\* BUILD SUCCEEDED \*\*' "$apple_log"; then
      grep -E 'error:' "$apple_log" | head -20 >&2
      echo "error: xcodebuild $build for $platform failed ($status)" >&2; exit 1
    fi
    echo "built $build for $platform"
  done
done
smoke_app() {  # $1 device name, $2 products subdirectory
  local udid
  udid="$(xcrun simctl list devices available | grep -F "    $1 (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')"
  [[ -n "$udid" ]] || { echo "error: no available simulator named '$1'" >&2; exit 1; }
  xcrun simctl boot "$udid" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcrun simctl install "$udid" "$apple_dd/Build/Products/$2/GamaStudio.app"
  local out
  set +e
  out="$(timeout 120 xcrun simctl launch --console-pty --terminate-running-process "$udid" com.donaldfilimon.GamaStudio --smoke 2>&1)"
  set -e
  grep -q 'gama-studio-app smoke: OK' <<<"$out" || { echo "$out" >&2; echo "error: launch smoke failed on $1" >&2; exit 1; }
  # ADR 0010: the app declares that it opens .usda in place, and a file
  # handed over at launch goes through the same open path as one from Files.
  # ADR 0011: that launch also opens it as a coordinated UIDocument, autosaves
  # an edit, reloads after another writer's coordinated write, and asks when
  # that write meets unsaved changes.
  local plist="$apple_dd/Build/Products/$2/GamaStudio.app/Info.plist"
  plutil -extract CFBundleDocumentTypes json -o - "$plist" | grep -q 'com.pixar.universal-scene-description-utf8' \
    || { echo "error: $2 app does not declare the .usda document type" >&2; exit 1; }
  [[ "$(plutil -extract LSSupportsOpeningDocumentsInPlace raw -o - "$plist")" == "true" ]] \
    || { echo "error: $2 app does not open documents in place" >&2; exit 1; }
  local data
  data="$(xcrun simctl get_app_container "$udid" com.donaldfilimon.GamaStudio data)"
  mkdir -p "$data/tmp"
  command cp -f Tests/GamaUSDTests/Fixtures/everything.usda "$data/tmp/gate-open.usda"
  set +e
  out="$(timeout 120 xcrun simctl launch --console-pty --terminate-running-process "$udid" com.donaldfilimon.GamaStudio --smoke --open "$data/tmp/gate-open.usda" 2>&1)"
  set -e
  grep -q 'gama-studio-app smoke: OK' <<<"$out" || { echo "$out" >&2; echo "error: open smoke failed on $1" >&2; exit 1; }
  echo "smoke OK on $1 (launch; open, autosave and coordination of a .usda)"
  # ADR 0012: unsaved Untitled changes survive a relaunch. The first launch
  # edits and waits for the recovery file to autosave, then exits as a kill
  # would; the second, with the same key, requires them restored as unsaved
  # Untitled changes, then opens a file and requires the recovery file gone.
  local key
  key="gate-$(uuidgen)"
  # ADR 0013: that launch also sweeps orphans. Plant one past the 7-day grace
  # period and one inside it; only the first may go.
  local recovery_dir="$data/Library/Application Support/GamaStudio Recovery"
  local old_orphan="$recovery_dir/gate-orphan-$(uuidgen).usda" young_orphan="$recovery_dir/gate-orphan-$(uuidgen).usda"
  mkdir -p "$recovery_dir"
  printf '#usda 1.0\n' >| "$old_orphan"
  printf '#usda 1.0\n' >| "$young_orphan"
  touch -t "$(date -v-8d +%Y%m%d%H%M)" "$old_orphan"
  set +e
  out="$(timeout 150 xcrun simctl launch --console-pty --terminate-running-process "$udid" com.donaldfilimon.GamaStudio --smoke --recovery-key "$key" --smoke-recovery write 2>&1)"
  set -e
  grep -q 'gama-studio-app smoke: OK' <<<"$out" || { echo "$out" >&2; echo "error: recovery write smoke failed on $1" >&2; exit 1; }
  [[ ! -e "$old_orphan" ]] || { echo "error: an orphaned recovery file past the grace period survived on $1" >&2; exit 1; }
  [[ -e "$young_orphan" ]] || { echo "error: an orphaned recovery file inside the grace period was deleted on $1" >&2; exit 1; }
  rm -f "$young_orphan"
  command cp -f Tests/GamaUSDTests/Fixtures/everything.usda "$data/tmp/gate-open.usda"
  set +e
  out="$(timeout 150 xcrun simctl launch --console-pty --terminate-running-process "$udid" com.donaldfilimon.GamaStudio --smoke --recovery-key "$key" --smoke-recovery restore --open "$data/tmp/gate-open.usda" 2>&1)"
  set -e
  grep -q 'gama-studio-app smoke: OK' <<<"$out" || { echo "$out" >&2; echo "error: recovery restore smoke failed on $1" >&2; exit 1; }
  echo "smoke OK on $1 (Untitled changes recovered after a relaunch; orphans swept after the grace period)"
  # ADR 0014: a window with no recovery file adopts the newest young orphan,
  # here one planted with the fixture's content; and discarding sessions
  # sweeps with them no longer live (the smoke discards made-up keys).
  local orphan="$recovery_dir/gate-orphan-$(uuidgen).usda" adopt_key="gate-$(uuidgen)" discard_key="gate-$(uuidgen)"
  command cp -f Tests/GamaUSDTests/Fixtures/everything.usda "$orphan"
  touch "$orphan"
  set +e
  out="$(timeout 150 xcrun simctl launch --console-pty --terminate-running-process "$udid" com.donaldfilimon.GamaStudio --smoke --recovery-key "$adopt_key" --adopt-orphans --smoke-recovery adopt --open "$data/tmp/gate-open.usda" 2>&1)"
  set -e
  grep -q 'gama-studio-app smoke: OK' <<<"$out" || { echo "$out" >&2; echo "error: recovery adopt smoke failed on $1" >&2; exit 1; }
  [[ ! -e "$orphan" ]] || { echo "error: the adopted orphan was left in place on $1" >&2; exit 1; }
  set +e
  out="$(timeout 150 xcrun simctl launch --console-pty --terminate-running-process "$udid" com.donaldfilimon.GamaStudio --smoke --recovery-key "$discard_key" --smoke-recovery discard 2>&1)"
  set -e
  grep -q 'gama-studio-app smoke: OK' <<<"$out" || { echo "$out" >&2; echo "error: recovery discard smoke failed on $1" >&2; exit 1; }
  rm -f "$recovery_dir/$adopt_key.usda" "$recovery_dir/$discard_key.usda"
  echo "smoke OK on $1 (orphan adopted; discarded sessions swept)"
}
smoke_app "${GAMA_STUDIO_IOS_SIMULATOR:-iPhone 17}" Debug-iphonesimulator
smoke_app "${GAMA_STUDIO_VISIONOS_SIMULATOR:-Apple Vision Pro}" Debug-xrsimulator

echo "check.sh: PASSED"
