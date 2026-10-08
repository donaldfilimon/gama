#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
ZIG=${GAMA_RUN_ZIG:-zig}
SESSION=${GAMA_RUN_SESSION:-gama}
[[ "$SESSION" =~ ^[a-zA-Z0-9_-]+$ ]] || { echo 'invalid session name' >&2; exit 64; }
STATE=${GAMA_RUN_STATE:-${TMPDIR:-/tmp}/gama-run-$UID}
ARTIFACTS=${GAMA_RUN_ARTIFACTS:-${TMPDIR:-/tmp}/gama-run-artifacts}
BINARY=${GAMA_RUN_BINARY:-$ROOT/zig-out/bin/demo}
OWNED_ID=''
TOKEN=''
owned() { [[ -n "$OWNED_ID" ]] && [[ "$(tmux show-option -v -t "$OWNED_ID" @gama-owner 2>/dev/null || true)" == "$TOKEN" ]]; }
cleanup() { local status=$?; if owned; then tmux send-keys -t "$OWNED_ID" C-c 2>/dev/null || true; sleep .2; if owned; then tmux kill-session -t "$OWNED_ID" 2>/dev/null || true; fi; fi; return "$status"; }
build() { [[ "$("$ZIG" version)" == "$(cat .zig-version)" ]] || { echo 'wrong Zig pin' >&2; return 1; }; "$ZIG" build -j2; }
launch() {
    command -v tmux >/dev/null
    [[ -x "$BINARY" ]] || { echo 'missing demo executable; run build' >&2; return 1; }
    if tmux has-session -t "=$SESSION" 2>/dev/null; then echo 'session name already exists; refusing takeover' >&2; return 1; fi
    [[ ! -L "$STATE" ]] || return 1
    mkdir -p "$STATE"; chmod 700 "$STATE"
    [[ ! -e "$STATE/$SESSION" ]] || { echo 'ownership receipt already exists' >&2; return 1; }
    TOKEN="$$-$RANDOM-$RANDOM"
    OWNED_ID=$(tmux new-session -d -P -F '#{session_id}' -s "$SESSION" -x 100 -y 30 "$BINARY" --gama-tui)
    tmux set-option -t "$OWNED_ID" @gama-owner "$TOKEN"
    (umask 077; printf '%s\n%s\n' "$OWNED_ID" "$TOKEN" > "$STATE/$SESSION")
}
load() { [[ -f "$STATE/$SESSION" && ! -L "$STATE/$SESSION" ]] || return 1; OWNED_ID=$(sed -n '1p' "$STATE/$SESSION"); TOKEN=$(sed -n '2p' "$STATE/$SESSION"); owned || { echo 'session ownership no longer matches' >&2; return 1; }; }
text() { owned || return 1; tmux capture-pane -p -t "$OWNED_ID"; }
assert_frame() {
    local expected=$1 label=$2 frame i
    for i in {1..50}; do frame=$(text) || return 1; if [[ "$frame" == *"$expected"* ]]; then printf '%s\n' "$frame" > "$ARTIFACTS/$label.txt"; return 0; fi; sleep .1; done
    printf 'missing frame assertion: %s\n%s\n' "$expected" "$frame" >&2; return 1
}
keys() { owned || return 1; tmux send-keys -t "$OWNED_ID" "$@"; }
case ${1:-smoke} in
 build) build ;;
 launch) launch ;;
 text) load; text ;;
 keys) shift; load; keys "$@" ;;
 quit) load; cleanup; rm -f "$STATE/$SESSION" ;;
 smoke)
    if [[ $# == 2 ]]; then BINARY=$2; else build; fi
    ARTIFACTS=$(mktemp -d "${ARTIFACTS}.XXXXXX"); chmod 700 "$ARTIFACTS"
    SESSION="${SESSION}-smoke-$$-$RANDOM"
    trap cleanup EXIT; trap 'exit 130' INT; trap 'exit 143' TERM; trap 'exit 129' HUP
    launch
    printf 'binary=%s\nzig=%s\nversion=%s\n' "$BINARY" "$ZIG" "$("$ZIG" version)" > "$ARTIFACTS/receipt.txt"
    assert_frame 'count 0 | focus -1' initial
    keys Tab; assert_frame 'focus +1' focus
    keys Enter; assert_frame 'count 1' activated
    keys Space; assert_frame 'count 2' space
    keys Tab; assert_frame 'focus name' form
    keys -l ab; assert_frame 'name [ab]' typed
    keys Left; keys -l X; assert_frame 'name [aXb]' inserted
    keys BSpace; assert_frame 'name [ab]' deleted
    keys Tab; assert_frame 'focus -1' away
    keys BTab; assert_frame 'focus name' returned
    assert_frame 'name [ab]' retained
    cleanup; OWNED_ID=''; rm -f "$STATE/$SESSION"
    printf 'PASS: counter, focus, editing, retained form; artifacts=%s\n' "$ARTIFACTS"
    ;;
 *) echo 'usage: driver.sh build|launch|text|keys ...|quit|smoke [built-binary]' >&2; exit 64 ;;
esac
