#!/usr/bin/env bash
set -euo pipefail

fake_counter_next() {
  local name="$1" value=0
  local file="$FAKE_STATE_DIR/$name"
  if [[ -f "$file" ]]; then
    read -r value < "$file"
  fi
  value=$((value + 1))
  printf '%s\n' "$value" > "$file"
  echo "$value"
}

fake_counter_current() {
  local name="$1" value=0
  local file="$FAKE_STATE_DIR/$name"
  if [[ -f "$file" ]]; then
    read -r value < "$file"
  fi
  echo "$value"
}

fake_adb() {
  local command_name="${1:-}" probe setting count
  printf 'adb|%s\n' "$*" >> "$FAKE_COMMAND_LOG"

  case "$command_name" in
    reconnect | wait-for-device)
      ;;
    shell)
      shift
      case "$*" in
        "service check package")
          probe="$(fake_counter_next readiness-probe)"
          if [[ "$FAKE_ADB_SCENARIO" == readiness-command-hangs ]]; then
            exec /bin/sleep 30
          fi
          if [[ "$FAKE_ADB_SCENARIO" == device-offline-then-install ]] \
            || { [[ "$FAKE_ADB_SCENARIO" == readiness-shell-retry ]] && ((probe == 1)); }; then
            echo "error: device offline" >&2
            return 1
          fi
          if [[ "$FAKE_ADB_SCENARIO" == readiness-exhausted ]] \
            || { [[ "$FAKE_ADB_SCENARIO" == readiness-package-retry ]] && ((probe == 1)); }; then
            echo "Service package: not found"
            return 1
          fi
          echo "Service package: found"
          ;;
        "settings get global window_animation_scale")
          probe="$(fake_counter_current readiness-probe)"
          if [[ "$FAKE_ADB_SCENARIO" == readiness-settings-retry ]] && ((probe == 1)); then
            echo "error: Broken pipe" >&2
            return 1
          fi
          echo 1
          ;;
        true)
          probe="$(fake_counter_current readiness-probe)"
          if [[ "$FAKE_ADB_SCENARIO" == device-offline-then-install ]] \
            || { [[ "$FAKE_ADB_SCENARIO" == readiness-shell-retry ]] && ((probe == 1)); }; then
            echo "error: shell transport unavailable" >&2
            return 1
          fi
          ;;
        "settings put global "*)
          setting="${4:-}"
          case "$FAKE_ADB_SCENARIO:$setting" in
            animation-retry:transition_animation_scale | shared-budget:transition_animation_scale)
              count="$(fake_counter_next transition-setting)"
              if ((count == 1)); then
                echo "error: Broken pipe" >&2
                return 1
              fi
              ;;
            animation-exhausted:window_animation_scale)
              echo "error: Broken pipe" >&2
              return 1
              ;;
          esac
          ;;
        *)
          echo "unexpected fake adb shell command: $*" >&2
          return 64
          ;;
      esac
      ;;
    install)
      count="$(fake_counter_next install)"
      if [[ "$FAKE_ADB_SCENARIO" == install-exhausted ]] \
        || { [[ "$FAKE_ADB_SCENARIO" == install-retry || "$FAKE_ADB_SCENARIO" == shared-budget ]] && ((count == 1)); }; then
        echo "Failure calling service package: Broken pipe" >&2
        return 1
      fi
      echo Success
      ;;
    *)
      echo "unexpected fake adb command: $*" >&2
      return 64
      ;;
  esac
}

case "$(basename "$0")" in
  adb)
    fake_adb "$@"
    exit $?
    ;;
  timeout)
    if [[ "${1:-}" != --signal=KILL ]]; then
      echo "unexpected timeout policy: ${1:-<missing>}" >&2
      exit 64
    fi
    shift
    duration="${1:?timeout duration is required}"
    shift
    printf 'timeout|%s|%s\n' "$duration" "$*" >> "$FAKE_COMMAND_LOG"
    if [[ "$FAKE_ADB_SCENARIO" == readiness-command-hangs ]]; then
      exec "$REAL_TIMEOUT" --signal=KILL "$duration" "$@"
    fi
    exec "$@"
    ;;
  sleep)
    printf 'sleep|%s\n' "${1:-}" >> "$FAKE_COMMAND_LOG"
    if [[ "$FAKE_ADB_SCENARIO" == readiness-exhausted ]]; then
      exec /bin/sleep "$@"
    fi
    exit 0
    ;;
esac

for variable in \
  GAMA_ANDROID_JOB_TIMEOUT_SECONDS \
  GAMA_ANDROID_PRE_EMULATOR_ALLOWANCE_SECONDS \
  GAMA_ANDROID_BOOT_ALLOWANCE_SECONDS \
  GAMA_ANDROID_POST_BOOT_CEILING_SECONDS \
  GAMA_ANDROID_JOB_HEADROOM_SECONDS \
  GAMA_ANDROID_RECOVERY_BUDGET \
  GAMA_ANDROID_INSTALL_RECOVERY_BUDGET \
  GAMA_ANDROID_GRADLE_PROJECT_CACHE_DIR \
  GAMA_ANDROID_GRADLE_BUILD_DIR \
  GAMA_ANDROID_CXX_BUILD_DIR \
  GAMA_ANDROID_GRADLE_TIMEOUT_SECONDS \
  GAMA_ANDROID_READINESS_DEADLINE_SECONDS \
  GAMA_ANDROID_READINESS_POLL_DELAY_SECONDS \
  GAMA_ANDROID_READY_PROBE_TIMEOUT_SECONDS \
  GAMA_ANDROID_RECONNECT_TIMEOUT_SECONDS \
  GAMA_ANDROID_WAIT_TIMEOUT_SECONDS \
  GAMA_ANDROID_RECOVERY_DELAY_SECONDS \
  GAMA_ANDROID_SETTINGS_TIMEOUT_SECONDS \
  GAMA_ANDROID_INSTALL_TIMEOUT_SECONDS \
  GAMA_ANDROID_CONTROL_TIMEOUT_SECONDS \
  GAMA_ANDROID_UI_DUMP_TIMEOUT_SECONDS \
  GAMA_ANDROID_OUTPUT_TIMEOUT_SECONDS \
  GAMA_ANDROID_LOGCAT_TIMEOUT_SECONDS \
  GAMA_ANDROID_POLL_DELAY_SECONDS \
  GAMA_ANDROID_POLL_ATTEMPTS \
  GAMA_ANDROID_DIAGNOSTIC_TIMEOUT_SECONDS \
  GAMA_ANDROID_FIXED_OVERHEAD_SECONDS; do
  unset "$variable"
done

TEST_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SELF="$TEST_ROOT/scripts/test-android-emulator-readiness.sh"
REAL_TIMEOUT="$(command -v timeout)"
export REAL_TIMEOUT
# shellcheck source=/dev/null
source "$TEST_ROOT/scripts/check-android-emulator.sh"

# Every GAMA_ANDROID_* knob the gate READS must also be DEFINED in it with a
# `:-default`. A merge that keeps a new reference while taking the other side's
# definitions leaves the gate dead under `set -u`, and because each case
# redirects output into a temp file the EXIT trap deletes, the death is silent:
# exit 1, zero output, no clue which name was missing. That merge has already
# happened once. This loop turns it into a named failure at the top of the run.
gate_script="$TEST_ROOT/scripts/check-android-emulator.sh"
undefined_knobs=()
while IFS= read -r knob; do
  grep -q "^${knob}=\"\${${knob}:-" "$gate_script" || undefined_knobs+=("$knob")
done < <(grep -oE '\$\{?GAMA_ANDROID_[A-Z_]+' "$gate_script" \
  | sed -E 's/^\$\{?//' | sort -u)
if ((${#undefined_knobs[@]} > 0)); then
  echo "error: referenced but never defaulted in check-android-emulator.sh:" >&2
  printf '  %s\n' "${undefined_knobs[@]}" >&2
  exit 1
fi

for external_path in \
  "$GAMA_ANDROID_GRADLE_PROJECT_CACHE_DIR" \
  "$GAMA_ANDROID_GRADLE_BUILD_DIR" \
  "$GAMA_ANDROID_CXX_BUILD_DIR"; do
  case "$external_path/" in
    "$PROJECT/"*)
      echo "error: Android Gradle/CMake scratch must stay outside the iCloud checkout" >&2
      exit 1
      ;;
  esac
done

test_tmp="$(mktemp -d "${TMPDIR:-/tmp}/gama-android-readiness.XXXXXX")"
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin"
ln -s "$SELF" "$test_tmp/bin/adb"
ln -s "$SELF" "$test_tmp/bin/timeout"
ln -s "$SELF" "$test_tmp/bin/sleep"
export PATH="$test_tmp/bin:$PATH"

CASE_INDEX=0
reset_case() {
  local scenario="$1" recovery_budget="$2"
  CASE_INDEX=$((CASE_INDEX + 1))
  FAKE_STATE_DIR="$test_tmp/case-$CASE_INDEX"
  FAKE_COMMAND_LOG="$FAKE_STATE_DIR/commands.log"
  FAKE_ADB_SCENARIO="$scenario"
  mkdir -p "$FAKE_STATE_DIR"
  : > "$FAKE_COMMAND_LOG"
  export FAKE_STATE_DIR FAKE_COMMAND_LOG FAKE_ADB_SCENARIO
  initialize_android_recovery_budget "$recovery_budget"
}

assert_equals() {
  local expected="$1" actual="$2" label="$3"
  if [[ "$actual" != "$expected" ]]; then
    echo "error: $label: expected '$expected', got '$actual'" >&2
    return 1
  fi
}

assert_log_count() {
  local expected="$1" pattern="$2" label="$3" actual
  actual="$(grep -c "$pattern" "$FAKE_COMMAND_LOG" || true)"
  assert_equals "$expected" "$actual" "$label"
}

assert_setting_order() {
  local expected actual
  expected="$(printf '%s\n' "$@")"
  actual="$(grep '^adb|shell settings put global ' "$FAKE_COMMAND_LOG" | sed 's/^adb|//')"
  assert_equals "$expected" "$actual" "ordered animation settings"
}

assert_setting_timeout_order() {
  local expected actual
  expected="$(printf '%s\n' "$@")"
  actual="$(grep '^timeout|5s|adb shell settings put global ' "$FAKE_COMMAND_LOG" \
    | sed 's/^timeout|5s|adb //')"
  assert_equals "$expected" "$actual" "ordered animation setting timeouts"
}

reset_case ready 2
wait_for_android_services >"$FAKE_STATE_DIR/output" 2>&1
assert_equals 1 "$ANDROID_READINESS_PROBES" "immediate readiness probes"
assert_equals 0 "$ANDROID_RECOVERIES_USED" "immediate readiness recoveries"

# A device that is present but whose services are still starting must be
# WAITED for, never reconnected: burning the shared budget here is what made
# a slow-but-healthy emulator fail the gate ~30s after boot.
reset_case readiness-package-retry 2
wait_for_android_services >"$FAKE_STATE_DIR/output" 2>&1
assert_equals 2 "$ANDROID_READINESS_PROBES" "package retry probes"
assert_equals 0 "$ANDROID_RECOVERIES_USED" "slow services consume no recovery"
assert_equals 2 "$ANDROID_RECOVERIES_REMAINING" "slow services preserve the budget"
assert_log_count 0 '^timeout|5s|adb reconnect$' "slow services do not reconnect"

reset_case readiness-settings-retry 2
wait_for_android_services >"$FAKE_STATE_DIR/output" 2>&1
assert_equals 2 "$ANDROID_READINESS_PROBES" "settings retry probes"
assert_equals 0 "$ANDROID_RECOVERIES_USED" "slow settings provider consumes no recovery"

# A broken shell transport must reconnect instead of waiting out the full
# service-readiness deadline.
reset_case readiness-shell-retry 2
wait_for_android_services >"$FAKE_STATE_DIR/output" 2>&1
assert_equals 2 "$ANDROID_READINESS_PROBES" "shell transport retry probes"
assert_equals 1 "$ANDROID_RECOVERIES_USED" "broken shell transport consumes one recovery"
assert_log_count 1 '^timeout|5s|adb reconnect$' "broken shell transport reconnects"

# Services that never arrive still fail closed at a real wall-clock deadline.
reset_case readiness-exhausted 2
readiness_started_at="$SECONDS"
if GAMA_ANDROID_READINESS_DEADLINE_SECONDS=2 \
  GAMA_ANDROID_READINESS_POLL_DELAY_SECONDS=1 \
  wait_for_android_services >"$FAKE_STATE_DIR/output" 2>&1; then
  echo "error: persistent readiness failure unexpectedly succeeded" >&2
  exit 1
fi
readiness_elapsed=$((SECONDS - readiness_started_at))
assert_equals 0 "$ANDROID_RECOVERIES_USED" "a present-but-dead device spends no reconnects"
if ((readiness_elapsed < 2 || readiness_elapsed > 4)); then
  echo "error: readiness wall-clock deadline took ${readiness_elapsed}s; expected 2-4s" >&2
  exit 1
fi
grep -q 'did not' "$FAKE_STATE_DIR/output"

# A readiness command that never returns is killed at the same deadline; the
# polling test above alone would not catch a timeout wrapper that only sent TERM.
reset_case readiness-command-hangs 2
readiness_started_at="$SECONDS"
if GAMA_ANDROID_READINESS_DEADLINE_SECONDS=2 \
  wait_for_android_services >"$FAKE_STATE_DIR/output" 2>&1; then
  echo "error: hanging readiness command unexpectedly succeeded" >&2
  exit 1
fi
readiness_elapsed=$((SECONDS - readiness_started_at))
if ((readiness_elapsed < 2 || readiness_elapsed > 4)); then
  echo "error: hanging readiness command took ${readiness_elapsed}s; expected 2-4s" >&2
  exit 1
fi
assert_equals 1 "$ANDROID_READINESS_PROBES" "hanging readiness probes"

reset_case animation-retry 1
configure_android_animations >"$FAKE_STATE_DIR/output" 2>&1
assert_equals 0 "$ANDROID_RECOVERIES_USED" "animation retry stays budget-free"
assert_equals 1 "$ANDROID_RECOVERIES_REMAINING" "animation retry preserves the budget"
assert_setting_order \
  'shell settings put global window_animation_scale 0' \
  'shell settings put global transition_animation_scale 0' \
  'shell settings put global window_animation_scale 0' \
  'shell settings put global transition_animation_scale 0' \
  'shell settings put global animator_duration_scale 0'
assert_setting_timeout_order \
  'shell settings put global window_animation_scale 0' \
  'shell settings put global transition_animation_scale 0' \
  'shell settings put global window_animation_scale 0' \
  'shell settings put global transition_animation_scale 0' \
  'shell settings put global animator_duration_scale 0'
assert_log_count 5 '^timeout|5s|adb shell settings put global ' "animation timeout count"

reset_case animation-exhausted 1
if ! configure_android_animations >"$FAKE_STATE_DIR/output" 2>&1; then
  echo "error: persistent animation failure was fatal; animations are best-effort" >&2
  exit 1
fi
assert_equals 0 "$ANDROID_RECOVERIES_USED" "persistent animation failure stays budget-free"
assert_equals 1 "$ANDROID_RECOVERIES_REMAINING" "persistent animation failure preserves the budget"
grep -q 'continuing WITH animations after 3 attempts' "$FAKE_STATE_DIR/output"
assert_setting_order \
  'shell settings put global window_animation_scale 0' \
  'shell settings put global window_animation_scale 0' \
  'shell settings put global window_animation_scale 0'

reset_case install-retry 1
install_android_apk /tmp/gama-fake.apk >"$FAKE_STATE_DIR/output" 2>&1
assert_equals 0 "$ANDROID_RECOVERIES_USED" "install retry leaves the shared budget untouched"
assert_equals 1 "$ANDROID_INSTALL_RECOVERIES_USED" "install retry consumes its own budget"
assert_equals 2 "$(fake_counter_current install)" "install retry attempts"
assert_log_count 2 '^timeout|90s|adb install -r /tmp/gama-fake.apk$' "install retry timeout count"

reset_case install-exhausted 2
if install_android_apk /tmp/gama-fake.apk >"$FAKE_STATE_DIR/output" 2>&1; then
  echo "error: persistent install failure unexpectedly succeeded" >&2
  exit 1
fi
assert_equals 0 "$ANDROID_RECOVERIES_USED" "install exhaustion leaves the shared budget untouched"
assert_equals 2 "$ANDROID_INSTALL_RECOVERIES_USED" "install exhaustion consumes its own budget"
assert_equals 3 "$(fake_counter_current install)" "install exhaustion attempts"
assert_log_count 3 '^timeout|90s|adb install -r /tmp/gama-fake.apk$' "install exhaustion timeout count"

# A device that goes offline during an EARLIER stage must not be able to
# consume the retries install needs — the regression that failed run
# 33074968908 (best-effort animations, then install starved of budget).
reset_case device-offline-then-install 2
if wait_for_android_services >"$FAKE_STATE_DIR/readiness-output" 2>&1; then
  echo "error: an offline device unexpectedly reported ready" >&2
  exit 1
fi
assert_equals 2 "$ANDROID_RECOVERIES_USED" "offline device exhausted the shared budget"
assert_equals 0 "$ANDROID_RECOVERIES_REMAINING" "offline device left no shared budget"
assert_equals 2 "$ANDROID_INSTALL_RECOVERIES_REMAINING" "install budget survives an offline device"

reset_case shared-budget 1
configure_android_animations >"$FAKE_STATE_DIR/animation-output" 2>&1
assert_equals 0 "$ANDROID_RECOVERIES_USED" "animation stage left the shared budget untouched"
if ! install_android_apk /tmp/gama-fake.apk >"$FAKE_STATE_DIR/install-output" 2>&1; then
  echo "error: install could not use its own recovery budget" >&2
  exit 1
fi
assert_equals 0 "$ANDROID_RECOVERIES_USED" "install never touches the shared budget"
assert_equals 1 "$ANDROID_RECOVERIES_REMAINING" "shared budget preserved for readiness"
assert_equals 1 "$ANDROID_INSTALL_RECOVERIES_USED" "install spent its own budget"
assert_equals 2 "$(fake_counter_current install)" "install retried on its own budget"

validate_android_time_budget
post_boot_max="$(calculate_android_post_boot_worst_case_seconds)"
allocated=$((
  GAMA_ANDROID_PRE_EMULATOR_ALLOWANCE_SECONDS
  + GAMA_ANDROID_BOOT_ALLOWANCE_SECONDS
  + GAMA_ANDROID_POST_BOOT_CEILING_SECONDS
  + GAMA_ANDROID_JOB_HEADROOM_SECONDS
))
assert_equals 1245 "$post_boot_max" "calculated conservative post-boot maximum"
assert_equals 3300 "$allocated" "55-minute job allocation"
((post_boot_max < GAMA_ANDROID_POST_BOOT_CEILING_SECONDS))
assert_equals 240 "$GAMA_ANDROID_JOB_HEADROOM_SECONDS" "job-level headroom"
assert_equals 30 "$GAMA_ANDROID_RECOVERY_DELAY_SECONDS" "service settle delay"
assert_equals 195 "$((GAMA_ANDROID_POST_BOOT_CEILING_SECONDS - post_boot_max))" "post-boot ceiling margin"

saved_post_boot_ceiling="$GAMA_ANDROID_POST_BOOT_CEILING_SECONDS"
GAMA_ANDROID_POST_BOOT_CEILING_SECONDS="$post_boot_max"
if validate_android_time_budget >"$test_tmp/invalid-budget.output" 2>&1; then
  echo "error: timing validation accepted a calculated maximum equal to the ceiling" >&2
  exit 1
fi
GAMA_ANDROID_POST_BOOT_CEILING_SECONDS="$saved_post_boot_ceiling"
validate_android_time_budget

saved_install_recovery_budget="$GAMA_ANDROID_INSTALL_RECOVERY_BUDGET"
GAMA_ANDROID_INSTALL_RECOVERY_BUDGET=invalid
if validate_android_time_budget >"$test_tmp/invalid-install-budget.output" 2>&1; then
  echo "error: timing validation accepted an invalid install recovery budget" >&2
  exit 1
fi
grep -q 'must be a nonnegative integer' "$test_tmp/invalid-install-budget.output"
GAMA_ANDROID_INSTALL_RECOVERY_BUDGET="$saved_install_recovery_budget"
validate_android_time_budget

reset_case ready 2
# An inner adb timeout exits 124 too; reporting that as the post-boot ceiling
# sends the next reader after a time budget that was never the problem.
if run_with_post_boot_ceiling sh -c 'exit 124' >"$FAKE_STATE_DIR/inner-timeout" 2>&1; then
  echo "error: an inner timeout was not treated as a failure" >&2
  exit 1
fi
if grep -q 'exceeded its' "$FAKE_STATE_DIR/inner-timeout"; then
  echo "error: an inner timeout was misreported as the post-boot ceiling" >&2
  exit 1
fi
grep -q 'well inside the' "$FAKE_STATE_DIR/inner-timeout"

reset_case ready 2
run_with_post_boot_ceiling true
assert_log_count 1 '^timeout|1440s|true$' "enforced post-boot ceiling"

echo "OK — isolated readiness/install budgets, stage exhaustion, timeout arguments, command order, and 55-minute envelope"
