#!/usr/bin/env bash
# driver.sh - agent harness for driving the Gama demos.
#
# The TUI needs a real tty, so the interactive commands run gama-demo inside
# a tmux session and read frames back with capture-pane. Every artifact lands
# under $GAMA_RUN_ARTIFACTS so a caller can inspect what the app actually drew.
#
# Usage: .claude/skills/run-gama/driver.sh <command> [args]
#   build            build the demo products with the pinned 6.5-dev snapshot
#   launch           start gama-demo in a detached tmux session (100x30)
#   keys <k>...      forward tmux send-keys arguments to the running app
#   snap [name]      write the current frame to $GAMA_RUN_ARTIFACTS/<name>.txt
#   text             print the current frame to stdout
#   count            print the demo's current counter value
#   focus            print the focused control's label (reads ANSI attributes)
#   quit             Ctrl-C the app and kill the session
#   mlir             direct invocation: emit the gama MLIR dialect (no tty)
#   smoke            launch, assert it rendered, drive focus with Tab, quit
#   apple            build and launch the AppKit multi-window demo
#
# Paths are relative to the repository root. Run from there.

set -euo pipefail

SCRATCH="${GAMA_RUN_SCRATCH:-/private/tmp/gama-run-skill}"
ARTIFACTS="${GAMA_RUN_ARTIFACTS:-/private/tmp/gama-run-artifacts}"
SESSION="${GAMA_RUN_SESSION:-gama-demo}"
PANE_WIDTH="${GAMA_RUN_WIDTH:-100}"
PANE_HEIGHT="${GAMA_RUN_HEIGHT:-30}"

# A stray TOOLCHAINS value overrides both the swiftly shim and the scripts'
# explicit xcrun pins, so it is cleared for every invocation.
unset TOOLCHAINS

swift_run() {
    swiftly run swift "$@"
}

require_tmux() {
    command -v tmux >/dev/null 2>&1 || {
        echo "driver: tmux is required (brew install tmux)" >&2
        exit 1
    }
}

cmd_build() {
    mkdir -p "$SCRATCH"
    swift_run build --scratch-path "$SCRATCH" \
        --product gama-demo
    echo "driver: built gama-demo at $SCRATCH/debug/gama-demo"
}

binary() {
    local bin="$SCRATCH/debug/gama-demo"
    [ -x "$bin" ] || {
        echo "driver: $bin missing; run '$0 build' first" >&2
        exit 1
    }
    printf '%s' "$bin"
}

cmd_launch() {
    require_tmux
    local bin
    bin="$(binary)"
    mkdir -p "$ARTIFACTS"
    tmux kill-session -t "$SESSION" 2>/dev/null || true
    # -x/-y pin the pane: the demo frame is 72x18 and clips in a smaller pane.
    tmux new-session -d -s "$SESSION" -x "$PANE_WIDTH" -y "$PANE_HEIGHT" "$bin"
    sleep 2
    tmux has-session -t "$SESSION" 2>/dev/null || {
        echo "driver: session died on launch" >&2
        exit 1
    }
    echo "driver: gama-demo running in tmux session '$SESSION'"
}

cmd_keys() {
    require_tmux
    tmux send-keys -t "$SESSION" "$@"
    # One frame of settle time: the loop repaints only while the host is dirty.
    sleep 1
}

cmd_text() {
    require_tmux
    tmux capture-pane -p -t "$SESSION"
}

cmd_snap() {
    local name="${1:-frame}"
    mkdir -p "$ARTIFACTS"
    cmd_text > "$ARTIFACTS/$name.txt"
    echo "$ARTIFACTS/$name.txt"
}

cmd_count() {
    # The StatBadge row renders as "count <n>"; the value may be negative.
    cmd_text | grep -o 'count *-\{0,1\}[0-9]\{1,\}' | head -1 | grep -o '\-\{0,1\}[0-9]\{1,\}'
}

cmd_focus() {
    require_tmux
    # The focus ring is an ANSI attribute run, so -p (which strips escapes)
    # cannot see it; -e keeps them. Teal 72;208;208 is the focused background.
    # Labels contain multibyte glyphs (the minus is U+2212), so the run is cut
    # at the next escape byte rather than passed through cat -v.
    tmux capture-pane -e -p -t "$SESSION" \
        | awk -v esc="$(printf '\033')" '
            {
                n = split($0, parts, esc "\\[48;2;72;208;208m")
                if (n > 1) {
                    label = parts[2]
                    sub(esc ".*", "", label)
                    gsub(/^ +| +$/, "", label)
                    if (label != "") { print label; exit }
                }
            }'
}

cmd_quit() {
    require_tmux
    tmux send-keys -t "$SESSION" C-c 2>/dev/null || true
    sleep 1
    tmux kill-session -t "$SESSION" 2>/dev/null || true
    echo "driver: session '$SESSION' stopped"
}

cmd_mlir() {
    # No tty needed: this path prints the dialect and exits.
    swift_run run --scratch-path "$SCRATCH" gama-demo --emit-mlir
}

cmd_smoke() {
    cmd_build
    cmd_launch
    local count before after
    count="$(cmd_count || true)"
    before="$(cmd_focus || true)"
    cmd_snap before >/dev/null
    if [ -z "$count" ]; then
        echo "driver: FAIL - the demo drew no counter on its first frame"
        cmd_quit
        exit 1
    fi
    if [ -z "$before" ]; then
        echo "driver: FAIL - no focus ring in the first frame"
        cmd_quit
        exit 1
    fi
    echo "driver: rendered (count=$count), focus on '$before'"
    # Tab moves the focus ring from '−1' to '+1' and the pane repaints live.
    cmd_keys Tab
    after="$(cmd_focus || true)"
    cmd_snap after >/dev/null
    echo "driver: focus after Tab: '$after'"
    if [ -z "$after" ] || [ "$before" = "$after" ]; then
        echo "driver: FAIL - Tab did not move the focus ring"
        cmd_quit
        exit 1
    fi
    # Enter activates the focused '+1' and the next frame must paint the
    # incremented count. CounterPanel is built inline in the scene closure,
    # so this is the per-surface @Reactive store (ADR 0011) working end to
    # end in a real tty, not just in the Swift Testing suite.
    local activated
    cmd_keys Enter
    sleep 0.7
    activated="$(cmd_count || true)"
    cmd_snap activated >/dev/null
    echo "driver: count after Enter on '$after': $activated"
    cmd_quit
    if [ -z "$activated" ] || [ "$activated" -ne $((count + 1)) ]; then
        echo "driver: FAIL - Enter on '$after' did not increment the count ($count -> '$activated')"
        exit 1
    fi
    echo "driver: PASS - launched, rendered, drove focus, and activated a control."
    echo "driver: frames in $ARTIFACTS (before.txt, after.txt, activated.txt)"
}

cmd_apple() {
    mkdir -p "$SCRATCH"
    swift_run build --scratch-path "$SCRATCH" --product gama-apple-demo
    echo "driver: launching the AppKit demo; it opens real windows and blocks."
    echo "driver: quit it with Command-Q, or Ctrl-C this shell."
    swift_run run --scratch-path "$SCRATCH" gama-apple-demo
}

case "${1:-}" in
    build) shift; cmd_build "$@" ;;
    launch) shift; cmd_launch "$@" ;;
    keys) shift; cmd_keys "$@" ;;
    snap) shift; cmd_snap "$@" ;;
    text) shift; cmd_text "$@" ;;
    count) shift; cmd_count "$@" ;;
    quit) shift; cmd_quit "$@" ;;
    focus) shift; cmd_focus "$@" ;;
    mlir) shift; cmd_mlir "$@" ;;
    smoke) shift; cmd_smoke "$@" ;;
    apple) shift; cmd_apple "$@" ;;
    *)
        sed -n '2,25p' "$0"
        exit 1
        ;;
esac
