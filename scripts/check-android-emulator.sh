#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/Examples/Android"

# The 45-minute job budget is partitioned explicitly. The setup allowance
# includes snapshot/SDK/NDK installation and cross-compilation; the boot
# allowance exceeds the observed ~648-second hosted boot. The final four
# minutes remain job-level headroom rather than being available to this script.
GAMA_ANDROID_JOB_TIMEOUT_SECONDS="${GAMA_ANDROID_JOB_TIMEOUT_SECONDS:-2700}"
GAMA_ANDROID_PRE_EMULATOR_ALLOWANCE_SECONDS="${GAMA_ANDROID_PRE_EMULATOR_ALLOWANCE_SECONDS:-900}"
GAMA_ANDROID_BOOT_ALLOWANCE_SECONDS="${GAMA_ANDROID_BOOT_ALLOWANCE_SECONDS:-720}"
GAMA_ANDROID_POST_BOOT_CEILING_SECONDS="${GAMA_ANDROID_POST_BOOT_CEILING_SECONDS:-840}"
GAMA_ANDROID_JOB_HEADROOM_SECONDS="${GAMA_ANDROID_JOB_HEADROOM_SECONDS:-240}"

# Every failed readiness or install stage consumes this same
# non-resetting recovery budget. No stage opens a nested retry window.
GAMA_ANDROID_RECOVERY_BUDGET="${GAMA_ANDROID_RECOVERY_BUDGET:-2}"
GAMA_ANDROID_GRADLE_TIMEOUT_SECONDS="${GAMA_ANDROID_GRADLE_TIMEOUT_SECONDS:-180}"
GAMA_ANDROID_READY_PROBE_TIMEOUT_SECONDS="${GAMA_ANDROID_READY_PROBE_TIMEOUT_SECONDS:-5}"
GAMA_ANDROID_RECONNECT_TIMEOUT_SECONDS="${GAMA_ANDROID_RECONNECT_TIMEOUT_SECONDS:-5}"
GAMA_ANDROID_WAIT_TIMEOUT_SECONDS="${GAMA_ANDROID_WAIT_TIMEOUT_SECONDS:-20}"
GAMA_ANDROID_RECOVERY_DELAY_SECONDS="${GAMA_ANDROID_RECOVERY_DELAY_SECONDS:-3}"
GAMA_ANDROID_SETTINGS_TIMEOUT_SECONDS="${GAMA_ANDROID_SETTINGS_TIMEOUT_SECONDS:-5}"
GAMA_ANDROID_INSTALL_TIMEOUT_SECONDS="${GAMA_ANDROID_INSTALL_TIMEOUT_SECONDS:-60}"
GAMA_ANDROID_CONTROL_TIMEOUT_SECONDS="${GAMA_ANDROID_CONTROL_TIMEOUT_SECONDS:-10}"
GAMA_ANDROID_UI_DUMP_TIMEOUT_SECONDS="${GAMA_ANDROID_UI_DUMP_TIMEOUT_SECONDS:-5}"
GAMA_ANDROID_OUTPUT_TIMEOUT_SECONDS="${GAMA_ANDROID_OUTPUT_TIMEOUT_SECONDS:-2}"
GAMA_ANDROID_LOGCAT_TIMEOUT_SECONDS="${GAMA_ANDROID_LOGCAT_TIMEOUT_SECONDS:-2}"
GAMA_ANDROID_POLL_DELAY_SECONDS="${GAMA_ANDROID_POLL_DELAY_SECONDS:-1}"
GAMA_ANDROID_POLL_ATTEMPTS="${GAMA_ANDROID_POLL_ATTEMPTS:-20}"
GAMA_ANDROID_DIAGNOSTIC_TIMEOUT_SECONDS="${GAMA_ANDROID_DIAGNOSTIC_TIMEOUT_SECONDS:-10}"
GAMA_ANDROID_FIXED_OVERHEAD_SECONDS="${GAMA_ANDROID_FIXED_OVERHEAD_SECONDS:-10}"

ANDROID_RECOVERIES_REMAINING=0
ANDROID_RECOVERIES_USED=0
ANDROID_RECOVERY_BUDGET_INITIAL=0
ANDROID_READINESS_PROBES=0

require_positive_integer() {
  local name="$1" value="$2"
  if [[ ! "$value" =~ ^[1-9][0-9]*$ ]]; then
    echo "error: $name must be a positive integer" >&2
    return 2
  fi
}

require_nonnegative_integer() {
  local name="$1" value="$2"
  if [[ ! "$value" =~ ^[0-9]+$ ]]; then
    echo "error: $name must be a nonnegative integer" >&2
    return 2
  fi
}

calculate_android_post_boot_worst_case_seconds() {
  local probe_max recovery_max animation_max install_max control_max poll_max
  probe_max=$((3 * GAMA_ANDROID_READY_PROBE_TIMEOUT_SECONDS))
  recovery_max=$((GAMA_ANDROID_RECOVERY_BUDGET * (
    GAMA_ANDROID_RECONNECT_TIMEOUT_SECONDS
    + GAMA_ANDROID_WAIT_TIMEOUT_SECONDS
    + GAMA_ANDROID_RECOVERY_DELAY_SECONDS
    + probe_max
  )))
  # Animations are best-effort: 3 bounded attempts of 3 settings each,
  # with 2 budget-free reconnect/wait/delay recoveries between attempts.
  animation_max=$((3 * 3 * GAMA_ANDROID_SETTINGS_TIMEOUT_SECONDS + 2 * (
    GAMA_ANDROID_RECONNECT_TIMEOUT_SECONDS
    + GAMA_ANDROID_WAIT_TIMEOUT_SECONDS
    + GAMA_ANDROID_RECOVERY_DELAY_SECONDS
  )))
  install_max=$((3 * GAMA_ANDROID_INSTALL_TIMEOUT_SECONDS))
  control_max=$((3 * GAMA_ANDROID_CONTROL_TIMEOUT_SECONDS))
  poll_max=$((GAMA_ANDROID_POLL_ATTEMPTS * (
    GAMA_ANDROID_UI_DUMP_TIMEOUT_SECONDS
    + GAMA_ANDROID_OUTPUT_TIMEOUT_SECONDS
    + GAMA_ANDROID_LOGCAT_TIMEOUT_SECONDS
    + GAMA_ANDROID_POLL_DELAY_SECONDS
  )))

  echo $((
    GAMA_ANDROID_GRADLE_TIMEOUT_SECONDS
    + probe_max
    + recovery_max
    + animation_max
    + install_max
    + control_max
    + poll_max
    + GAMA_ANDROID_DIAGNOSTIC_TIMEOUT_SECONDS
    + GAMA_ANDROID_FIXED_OVERHEAD_SECONDS
  ))
}

validate_android_time_budget() {
  local name value post_boot_max allocated
  for name in \
    GAMA_ANDROID_JOB_TIMEOUT_SECONDS \
    GAMA_ANDROID_PRE_EMULATOR_ALLOWANCE_SECONDS \
    GAMA_ANDROID_BOOT_ALLOWANCE_SECONDS \
    GAMA_ANDROID_POST_BOOT_CEILING_SECONDS \
    GAMA_ANDROID_JOB_HEADROOM_SECONDS \
    GAMA_ANDROID_GRADLE_TIMEOUT_SECONDS \
    GAMA_ANDROID_READY_PROBE_TIMEOUT_SECONDS \
    GAMA_ANDROID_RECONNECT_TIMEOUT_SECONDS \
    GAMA_ANDROID_WAIT_TIMEOUT_SECONDS \
    GAMA_ANDROID_SETTINGS_TIMEOUT_SECONDS \
    GAMA_ANDROID_INSTALL_TIMEOUT_SECONDS \
    GAMA_ANDROID_CONTROL_TIMEOUT_SECONDS \
    GAMA_ANDROID_UI_DUMP_TIMEOUT_SECONDS \
    GAMA_ANDROID_OUTPUT_TIMEOUT_SECONDS \
    GAMA_ANDROID_LOGCAT_TIMEOUT_SECONDS \
    GAMA_ANDROID_POLL_ATTEMPTS \
    GAMA_ANDROID_DIAGNOSTIC_TIMEOUT_SECONDS \
    GAMA_ANDROID_FIXED_OVERHEAD_SECONDS; do
    value="${!name}"
    require_positive_integer "$name" "$value"
  done
  require_nonnegative_integer GAMA_ANDROID_RECOVERY_BUDGET "$GAMA_ANDROID_RECOVERY_BUDGET"
  require_nonnegative_integer GAMA_ANDROID_RECOVERY_DELAY_SECONDS "$GAMA_ANDROID_RECOVERY_DELAY_SECONDS"
  require_nonnegative_integer GAMA_ANDROID_POLL_DELAY_SECONDS "$GAMA_ANDROID_POLL_DELAY_SECONDS"

  post_boot_max="$(calculate_android_post_boot_worst_case_seconds)"
  if ((post_boot_max >= GAMA_ANDROID_POST_BOOT_CEILING_SECONDS)); then
    echo "error: calculated Android post-boot maximum ${post_boot_max}s must stay below the enforced ${GAMA_ANDROID_POST_BOOT_CEILING_SECONDS}s ceiling" >&2
    return 1
  fi

  allocated=$((
    GAMA_ANDROID_PRE_EMULATOR_ALLOWANCE_SECONDS
    + GAMA_ANDROID_BOOT_ALLOWANCE_SECONDS
    + GAMA_ANDROID_POST_BOOT_CEILING_SECONDS
    + GAMA_ANDROID_JOB_HEADROOM_SECONDS
  ))
  if ((allocated > GAMA_ANDROID_JOB_TIMEOUT_SECONDS)); then
    echo "error: Android timing allocation ${allocated}s exceeds the ${GAMA_ANDROID_JOB_TIMEOUT_SECONDS}s job timeout" >&2
    return 1
  fi
}

describe_android_time_budget() {
  local post_boot_max allocated
  post_boot_max="$(calculate_android_post_boot_worst_case_seconds)"
  allocated=$((
    GAMA_ANDROID_PRE_EMULATOR_ALLOWANCE_SECONDS
    + GAMA_ANDROID_BOOT_ALLOWANCE_SECONDS
    + GAMA_ANDROID_POST_BOOT_CEILING_SECONDS
    + GAMA_ANDROID_JOB_HEADROOM_SECONDS
  ))
  echo "Android timing envelope: calculated post-boot maximum ${post_boot_max}s < enforced ${GAMA_ANDROID_POST_BOOT_CEILING_SECONDS}s ceiling; ${allocated}s allocated within ${GAMA_ANDROID_JOB_TIMEOUT_SECONDS}s job"
}

run_with_timeout() {
  local seconds="$1"
  shift
  timeout "${seconds}s" "$@"
}

initialize_android_recovery_budget() {
  local budget="${1:-$GAMA_ANDROID_RECOVERY_BUDGET}"
  require_nonnegative_integer Android_recovery_budget "$budget"
  ANDROID_RECOVERIES_REMAINING="$budget"
  ANDROID_RECOVERIES_USED=0
  ANDROID_RECOVERY_BUDGET_INITIAL="$budget"
  ANDROID_READINESS_PROBES=0
}

consume_android_recovery() {
  local stage="$1"
  if ((ANDROID_RECOVERIES_REMAINING == 0)); then
    echo "error: shared Android recovery budget exhausted while $stage" >&2
    return 1
  fi
  ANDROID_RECOVERIES_REMAINING=$((ANDROID_RECOVERIES_REMAINING - 1))
  ANDROID_RECOVERIES_USED=$((ANDROID_RECOVERIES_USED + 1))
  echo "warning: consuming shared Android recovery $ANDROID_RECOVERIES_USED/$ANDROID_RECOVERY_BUDGET_INITIAL for $stage" >&2
}

recover_android_connection() {
  run_with_timeout "$GAMA_ANDROID_RECONNECT_TIMEOUT_SECONDS" adb reconnect >/dev/null 2>&1 || true
  run_with_timeout "$GAMA_ANDROID_WAIT_TIMEOUT_SECONDS" adb wait-for-device >/dev/null 2>&1 || true
}

android_services_ready() {
  local state package_status
  ANDROID_READINESS_PROBES=$((ANDROID_READINESS_PROBES + 1))

  state="$(run_with_timeout "$GAMA_ANDROID_READY_PROBE_TIMEOUT_SECONDS" adb get-state 2>/dev/null)" || return 1
  [[ "$state" == device ]] || return 1

  package_status="$(run_with_timeout "$GAMA_ANDROID_READY_PROBE_TIMEOUT_SECONDS" adb shell service check package 2>/dev/null)" || return 1
  [[ "$package_status" == *"Service package: found"* ]] || return 1

  # A non-mutating read proves the same settings-provider path used by
  # `settings put` is alive without changing state during the probe.
  run_with_timeout "$GAMA_ANDROID_READY_PROBE_TIMEOUT_SECONDS" \
    adb shell settings get global window_animation_scale >/dev/null 2>&1
}

recover_until_android_services_ready() {
  local stage="$1"
  while true; do
    consume_android_recovery "$stage" || return 1
    recover_android_connection
    sleep "$GAMA_ANDROID_RECOVERY_DELAY_SECONDS"
    if android_services_ready; then
      echo "Android adb, package manager, and settings provider recovered"
      return 0
    fi
    echo "warning: Android services still unavailable after recovery" >&2
  done
}

wait_for_android_services() {
  if android_services_ready; then
    echo "Android adb, package manager, and settings provider ready"
    return 0
  fi

  echo "warning: Android services not initially ready" >&2
  if ! recover_until_android_services_ready "initial service readiness"; then
    echo "error: Android adb, package manager, and settings provider did not become ready" >&2
    return 1
  fi
}

set_android_animation_scales_once() {
  run_with_timeout "$GAMA_ANDROID_SETTINGS_TIMEOUT_SECONDS" \
    adb shell settings put global window_animation_scale 0 \
    && run_with_timeout "$GAMA_ANDROID_SETTINGS_TIMEOUT_SECONDS" \
      adb shell settings put global transition_animation_scale 0 \
    && run_with_timeout "$GAMA_ANDROID_SETTINGS_TIMEOUT_SECONDS" \
      adb shell settings put global animator_duration_scale 0
}

configure_android_animations() {
  # Best-effort: animations only add input/frame latency, and the strict
  # gate is the input/frame round trip below. Retries are bounded and do
  # NOT consume the shared recovery budget, which stays reserved for the
  # load-bearing readiness and install stages (a hosted run exhausted the
  # budget here during a slow settings-provider settle and failed the job
  # before the real test ran).
  local attempt
  for attempt in 1 2 3; do
    if set_android_animation_scales_once; then
      echo "Android emulator animations disabled"
      return 0
    fi
    echo "warning: Android animation settings failed on attempt $attempt" >&2
    if ((attempt < 3)); then
      recover_android_connection
      sleep "$GAMA_ANDROID_RECOVERY_DELAY_SECONDS"
    fi
  done
  echo "warning: continuing WITH animations after 3 attempts; the input/frame round trip remains the strict gate" >&2
  return 0
}

install_android_apk() {
  local apk="$1" attempt
  for attempt in 1 2 3; do
    if run_with_timeout "$GAMA_ANDROID_INSTALL_TIMEOUT_SECONDS" adb install -r "$apk"; then
      echo "Android APK installed"
      return 0
    fi

    echo "warning: adb install attempt $attempt failed" >&2
    if ((attempt < 3)); then
      if ! recover_until_android_services_ready "APK install"; then
        echo "error: Android APK install could not recover within the shared recovery budget" >&2
        return 1
      fi
    fi
  done

  echo "error: Android APK install failed after 3 attempts" >&2
  return 1
}

run_android_runtime_assertion() {
  local attempt
  run_with_timeout "$GAMA_ANDROID_CONTROL_TIMEOUT_SECONDS" adb shell am force-stop com.gama.example
  run_with_timeout "$GAMA_ANDROID_CONTROL_TIMEOUT_SECONDS" adb logcat -c
  run_with_timeout "$GAMA_ANDROID_CONTROL_TIMEOUT_SECONDS" \
    adb shell am start -W -n com.gama.example/.MainActivity >/dev/null

  for ((attempt = 1; attempt <= GAMA_ANDROID_POLL_ATTEMPTS; attempt++)); do
    # A wedged accessibility service can otherwise make one dump consume minutes.
    run_with_timeout "$GAMA_ANDROID_UI_DUMP_TIMEOUT_SECONDS" \
      adb shell uiautomator dump /sdcard/gama-window.xml >/dev/null 2>&1 || true
    if run_with_timeout "$GAMA_ANDROID_OUTPUT_TIMEOUT_SECONDS" \
      adb exec-out cat /sdcard/gama-window.xml 2>/dev/null \
      | grep -q 'GAMA_OK 40 12 CHANGED'; then
      echo "OK — Android emulator JNI input mutated and rendered a decoded frame"
      return 0
    fi
    if run_with_timeout "$GAMA_ANDROID_LOGCAT_TIMEOUT_SECONDS" \
      adb logcat -d -s GamaAcceptance:I '*:S' \
      | grep -q 'GAMA_OK 40 12 CHANGED'; then
      echo "OK — Android emulator JNI input mutated and rendered a decoded frame"
      return 0
    fi
    sleep "$GAMA_ANDROID_POLL_DELAY_SECONDS"
  done

  run_with_timeout "$GAMA_ANDROID_DIAGNOSTIC_TIMEOUT_SECONDS" \
    adb logcat -d -t 400 >&2 || true
  echo "error: Android UI never exposed the GAMA_OK runtime assertion" >&2
  return 1
}

run_android_post_boot_gate() {
  : "${ANDROID_HOME:?ANDROID_HOME is required for the Android emulator gate}"
  command -v adb >/dev/null
  command -v gradle >/dev/null
  command -v timeout >/dev/null
  test -f "$PROJECT/app/src/main/jniLibs/x86_64/libGamaAndroidDemo.so"
  (
    cd "$PROJECT"
    run_with_timeout "$GAMA_ANDROID_GRADLE_TIMEOUT_SECONDS" \
      gradle --no-daemon :app:assembleDebug
  )
  local apk="$PROJECT/app/build/outputs/apk/debug/app-debug.apk"
  test -f "$apk"

  wait_for_android_services
  configure_android_animations
  install_android_apk "$apk"
  run_android_runtime_assertion
}

run_with_post_boot_ceiling() {
  local status
  set +e
  timeout "${GAMA_ANDROID_POST_BOOT_CEILING_SECONDS}s" "$@"
  status=$?
  set -e
  if ((status == 124 || status == 137)); then
    echo "error: Android post-boot gate exceeded its ${GAMA_ANDROID_POST_BOOT_CEILING_SECONDS}s ceiling" >&2
    return 1
  fi
  return "$status"
}

main() {
  validate_android_time_budget
  command -v timeout >/dev/null

  if [[ "${1:-}" == --post-boot-child ]]; then
    initialize_android_recovery_budget
    run_android_post_boot_gate
    return
  fi

  describe_android_time_budget
  run_with_post_boot_ceiling "$0" --post-boot-child
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
