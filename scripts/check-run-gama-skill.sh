#!/usr/bin/env bash
# Keep both tracked run-gama discovery entry points equivalent, and prove that
# an interrupted smoke removes stale evidence and releases its owned session.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AGENTS_DIR="$ROOT/.agents/skills/run-gama"
CLAUDE_DIR="$ROOT/.claude/skills/run-gama"

for required_file in \
    "$AGENTS_DIR/SKILL.md" \
    "$AGENTS_DIR/driver.sh" \
    "$CLAUDE_DIR/SKILL.md" \
    "$CLAUDE_DIR/driver.sh"; do
    if [ ! -f "$required_file" ]; then
        echo "error: required run-gama entry point is missing: $required_file" >&2
        exit 1
    fi
done

normalize_agents() {
    sed 's#\.agents/skills/run-gama#<run-gama-skill>#g' "$1"
}

normalize_claude() {
    sed 's#\.claude/skills/run-gama#<run-gama-skill>#g' "$1"
}

entry_path_is_valid() {
    local file="$1"
    local own_prefix="$2"
    local foreign_prefix="$3"
    grep -Fq "$own_prefix" "$file" && ! grep -Fq "$foreign_prefix" "$file"
}

for skill_file in SKILL.md driver.sh; do
    agents_file="$AGENTS_DIR/$skill_file"
    claude_file="$CLAUDE_DIR/$skill_file"
    if ! entry_path_is_valid \
        "$agents_file" \
        '.agents/skills/run-gama' \
        '.claude/skills/run-gama'; then
        echo "error: $agents_file must name only its .agents entry point" >&2
        exit 1
    fi
    if ! entry_path_is_valid \
        "$claude_file" \
        '.claude/skills/run-gama' \
        '.agents/skills/run-gama'; then
        echo "error: $claude_file must name only its .claude entry point" >&2
        exit 1
    fi
    if ! diff -u \
        <(normalize_agents "$agents_file") \
        <(normalize_claude "$claude_file"); then
        echo "error: run-gama $skill_file entry points have drifted" >&2
        exit 1
    fi
done
for driver in "$AGENTS_DIR/driver.sh" "$CLAUDE_DIR/driver.sh"; do
    if [ ! -x "$driver" ]; then
        echo "error: $driver is not executable" >&2
        exit 1
    fi
done

TEST_ROOT="$(mktemp -d /private/tmp/gama-run-driver-test.XXXXXX)"
signal_pid=""
cleanup_test_root() {
    trap - EXIT INT TERM HUP
    if [ -n "$signal_pid" ]; then
        kill -TERM "$signal_pid" 2>/dev/null || true
        wait "$signal_pid" 2>/dev/null || true
    fi
    rm -rf -- "$TEST_ROOT"
}
check_interrupt() {
    exit "$1"
}
trap cleanup_test_root EXIT
trap 'check_interrupt 130' INT
trap 'check_interrupt 143' TERM
trap 'check_interrupt 129' HUP

printf '%s\n' '.claude/skills/run-gama' > "$TEST_ROOT/agents-wrong-path"
if entry_path_is_valid \
    "$TEST_ROOT/agents-wrong-path" \
    '.agents/skills/run-gama' \
    '.claude/skills/run-gama'; then
    echo "error: run-gama path check accepted a same-path .agents mirror" >&2
    exit 1
fi
printf '%s\n' '.agents/skills/run-gama' > "$TEST_ROOT/claude-wrong-path"
if entry_path_is_valid \
    "$TEST_ROOT/claude-wrong-path" \
    '.claude/skills/run-gama' \
    '.agents/skills/run-gama'; then
    echo "error: run-gama path check accepted swapped entry-point paths" >&2
    exit 1
fi

export GAMA_RUN_SCRATCH="$TEST_ROOT/scratch"
export GAMA_RUN_ARTIFACTS="$TEST_ROOT/artifacts"
export GAMA_RUN_SESSION="gama-run-driver-test-$$"

# Sourcing is intentional: the public command dispatcher is guarded so this
# test can replace external build/tmux operations with deterministic doubles.
# shellcheck source=/dev/null
source "$AGENTS_DIR/driver.sh"

seed_stale_artifacts() {
    mkdir -p "$ARTIFACTS"
    for artifact in before.txt after.txt activated.txt; do
        printf '%s\n' stale > "$ARTIFACTS/$artifact"
    done
}

assert_artifacts_absent() {
    for artifact in before.txt after.txt activated.txt; do
        if [ -e "$ARTIFACTS/$artifact" ]; then
            echo "error: run-gama smoke retained stale $artifact after failure" >&2
            exit 1
        fi
    done
}

assert_private_session() {
    case "$SMOKE_RUN_ID" in
        "smoke-$$-"*) ;;
        *)
            echo "error: run-gama smoke did not select a private session name" >&2
            return 42
            ;;
    esac
    if [ "$SESSION" != "${SESSION_PREFIX}-${SMOKE_RUN_ID}" ]; then
        echo "error: run-gama session does not match its private run ID" >&2
        return 42
    fi
    if [ "$ARTIFACTS" != "${ARTIFACTS_ROOT}/${SMOKE_RUN_ID}" ]; then
        echo "error: run-gama artifacts do not match their private run ID" >&2
        return 42
    fi
}

SMOKE_RUN_PREPARED=0
prepare_smoke_run
seed_stale_artifacts
# These first doubles are invoked indirectly before the later redefinitions.
# shellcheck disable=SC2329
cmd_build() { return 41; }
# shellcheck disable=SC2329
cmd_launch() { return 99; }

set +e
(
    set -e
    cmd_smoke
) > "$TEST_ROOT/build-failure-output.txt" 2>&1
build_status=$?
set -e

if [ "$build_status" -ne 41 ]; then
    echo "error: run-gama build failure status changed from 41 to $build_status" >&2
    exit 1
fi
assert_artifacts_absent
test ! -e "$TEST_ROOT/cleanup-marker" || {
    echo "error: run-gama tried to release a session it did not own" >&2
    exit 1
}

SMOKE_RUN_PREPARED=0
prepare_smoke_run
cmd_build() { :; }
# This signal double is invoked indirectly before the later redefinition.
# shellcheck disable=SC2329
cmd_launch() {
    assert_private_session
    # The sourced signal and cleanup traps consume this ownership marker.
    # shellcheck disable=SC2034
    SMOKE_SESSION_OWNED=1
    printf '%s\n' ready > "$TEST_ROOT/signal-ready"
    while :; do
        sleep 1
    done
}
# shellcheck disable=SC2329
cmd_quit() {
    printf '%s\n' cleaned > "$TEST_ROOT/signal-cleanup-marker"
}

seed_stale_artifacts
(
    set -e
    cmd_smoke
) > "$TEST_ROOT/signal-output.txt" 2>&1 &
signal_pid=$!
signal_ready=0
for _ in {1..50}; do
    if [ -f "$TEST_ROOT/signal-ready" ]; then
        signal_ready=1
        break
    fi
    sleep 0.1
done
if [ "$signal_ready" -ne 1 ]; then
    kill -TERM "$signal_pid" 2>/dev/null || true
    wait "$signal_pid" 2>/dev/null || true
    signal_pid=""
    echo "error: run-gama signal negative control never reached launch" >&2
    exit 1
fi
kill -TERM "$signal_pid"
set +e
wait "$signal_pid"
signal_status=$?
signal_pid=""
set -e

if [ "$signal_status" -ne 143 ]; then
    echo "error: run-gama TERM status was $signal_status instead of 143" >&2
    exit 1
fi
test -f "$TEST_ROOT/signal-cleanup-marker" || {
    echo "error: run-gama TERM trap did not release the owned session" >&2
    exit 1
}
assert_artifacts_absent

# The sourced preparation function consumes this reset.
# shellcheck disable=SC2034
SMOKE_RUN_PREPARED=0
prepare_smoke_run
cmd_launch() {
    assert_private_session
    # The sourced cleanup trap consumes this ownership marker.
    # shellcheck disable=SC2034
    SMOKE_SESSION_OWNED=1
}
cmd_count() { printf '%s\n' 0; }
cmd_focus() { printf '%s\n' '−1'; }
cmd_snap() { return 37; }
cmd_quit() {
    printf '%s\n' cleaned > "$TEST_ROOT/cleanup-marker"
}

seed_stale_artifacts
set +e
(
    set -e
    cmd_smoke
) > "$TEST_ROOT/smoke-output.txt" 2>&1
smoke_status=$?
set -e

if [ "$smoke_status" -ne 37 ]; then
    echo "error: run-gama cleanup trap changed failure status 37 to $smoke_status" >&2
    exit 1
fi
test -f "$TEST_ROOT/cleanup-marker" || {
    echo "error: run-gama cleanup trap did not release the owned session" >&2
    exit 1
}
assert_artifacts_absent

echo "OK - run-gama mirrors and failure cleanup"
