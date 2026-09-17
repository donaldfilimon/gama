#!/usr/bin/env bash
# profile-apple-host.sh — trace-backed profiling of the native Apple host.
#
# Roadmap Task 5 accepts the six-way GamaAppleUI/GamaAppleShell split only
# when median CPU, allocations, and peak memory are no worse than 5% against a
# baseline, and it allows an optimization claim only on a >=10% median
# improvement across five identical release runs. A baseline captured after
# the split proves nothing, so this script exists to capture it before.
#
# It drives the RELEASE `gama-apple-demo` through its deterministic
# `--scenario` mode (Sources/GamaAppleDemo/Scenario.swift) and produces:
#
#   1. N identical bare release runs — the numbers that go in the baseline
#      table in docs/Performance.md.
#   2. An Instruments Time Profiler trace, for attribution.
#   3. An Instruments Allocations trace, for allocation counts (which no
#      plain Darwin process can count for itself; see docs/Performance.md).
#
# Bare timings and traced timings are never mixed: recording under
# Instruments perturbs the numbers, so a traced run is evidence about *where*
# time goes, never about how much.
#
# This is NOT a gate. It asserts no threshold and is absent from check.sh.
#
# Usage:
#   scripts/profile-apple-host.sh [--runs N] [--frames N] [--warmup N]
#                                 [--trace-frames N] [--out DIR] [--no-trace]
set -euo pipefail
unset TOOLCHAINS || true

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH="${GAMA_APPLE_PROFILE_SCRATCH_PATH:-/private/tmp/gama-apple-perf-build}"
OUT="${GAMA_APPLE_PROFILE_OUT:-/private/tmp/gama-apple-profile}"
RUNS=5
# 150/30 rather than gama-bench's 2000/200: on current main the scenario
# aborts inside CoreText after a few hundred frames (docs/Performance.md,
# "Per-command font creation aborts the host"). Raise these to the bench
# convention once that fix lands — the harness itself has no such limit.
FRAMES=150
WARMUP=30
TRACE_FRAMES=150
# A wall-clock ceiling on each recording. Instruments' Allocations injection
# can deadlock the target inside `liboainject.dylib` before `main` runs, in
# which case the recorder waits forever; without a limit that hangs the whole
# script rather than reporting a failure.
TRACE_TIME_LIMIT="${GAMA_APPLE_TRACE_TIME_LIMIT:-120s}"
# `--time-limit` alone is not enough: when the target deadlocks before `main`
# the recorder never starts its clock and waits indefinitely, so the script
# also enforces its own wall-clock watchdog. (`timeout`/`gtimeout` are not
# installed on this machine, hence the hand-rolled poll.)
TRACE_WALL_LIMIT="${GAMA_APPLE_TRACE_WALL_LIMIT:-180}"
DO_TRACE=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --runs) RUNS="$2"; shift 2 ;;
    --frames) FRAMES="$2"; shift 2 ;;
    --warmup) WARMUP="$2"; shift 2 ;;
    --trace-frames) TRACE_FRAMES="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --no-trace) DO_TRACE=0; shift ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "error: unknown argument $1" >&2; exit 64 ;;
  esac
done

# The scratch path must stay outside the iCloud-managed checkout: an in-place
# build fails at codesign with "resource fork ... not allowed".
case "$SCRATCH" in
  "$ROOT"/*) echo "error: scratch path must be outside the checkout" >&2; exit 1 ;;
esac

SWIFT=(/usr/bin/xcrun --toolchain "${GAMA_TOOLCHAIN_ID:-org.swift.65202608211a}" swift)
version="$("${SWIFT[@]}" --version)"
grep -q 'Swift version 6.5' <<<"$version" || {
  echo "error: Apple host profiling requires Swift 6.5" >&2; echo "$version" >&2; exit 1
}

mkdir -p "$OUT"
COMMIT="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"

echo "== building release gama-apple-demo (scratch $SCRATCH)"
"${SWIFT[@]}" build -c release --package-path "$ROOT" --scratch-path "$SCRATCH" \
  --product gama-apple-demo
BINARY="$SCRATCH/release/gama-apple-demo"
[[ -x "$BINARY" ]] || { echo "error: $BINARY is not executable" >&2; exit 1; }

echo "== $RUNS bare release runs (frames=$FRAMES warmup=$WARMUP)"
# On current main the scenario aborts probabilistically inside CoreText (see
# "Per-command font creation aborts the host" in docs/Performance.md). An
# aborted run yields no samples at all, so retrying it is not selecting among
# timings — but the abort count is reported, never swallowed.
aborts=0
for ((run = 1; run <= RUNS; run++)); do
  log="$OUT/run-$run.txt"
  completed=0
  for attempt in 1 2 3 4 5 6 7 8; do
    # Exit status comes from the command itself, never from a pipeline tail.
    if "$BINARY" --scenario --frames "$FRAMES" --warmup "$WARMUP" >"$log" 2>&1; then
      completed=1
      break
    fi
    aborts=$((aborts + 1))
    # /bin/cp, not cp: an interactive `cp -i` alias would silently no-op here.
    /bin/cp -f "$log" "$OUT/abort-$run-$attempt.txt"
  done
  if [[ $completed -eq 0 ]]; then
    echo "error: bare run $run never completed; last output follows" >&2
    cat "$log" >&2
    exit 1
  fi
  echo "  run $run -> $log"
done
echo "  aborted attempts discarded: $aborts (see $OUT/abort-*.txt)"
echo "$aborts" >"$OUT/aborts.txt"

echo
python3 - "$OUT" "$RUNS" "$COMMIT" <<'PY'
import sys, statistics, os
out, runs, commit = sys.argv[1], int(sys.argv[2]), sys.argv[3]
phases, digests = {}, {}
for run in range(1, runs + 1):
    with open(os.path.join(out, f"run-{run}.txt")) as handle:
        for line in handle:
            parts = line.rstrip("\n").split("\t")
            if parts[0] == "BENCH":
                phases.setdefault(parts[1], []).append((int(parts[3]), int(parts[4])))
            elif parts[0] == "DIGEST":
                digests.setdefault(parts[1], set()).add(parts[2])
width = max((len(name) for name in phases), default=10)
print(f"aggregate over {runs} bare release runs @ {commit}")
print(f"{'phase'.ljust(width)}  {'median ns':>12}  {'spread':>8}  {'p95 ns':>12}")
for name, values in phases.items():
    medians = sorted(v[0] for v in values)
    p95s = sorted(v[1] for v in values)
    spread = (medians[-1] - medians[0]) / medians[len(medians) // 2] if medians[len(medians)//2] else 0
    print(f"{name.ljust(width)}  {statistics.median(medians):>12.0f}  "
          f"{spread * 100:>7.1f}%  {statistics.median(p95s):>12.0f}")
print()
for kind, values in digests.items():
    verdict = "IDENTICAL across runs" if len(values) == 1 else f"DIVERGED: {sorted(values)}"
    print(f"{kind} digest: {verdict}")
PY

if [[ $DO_TRACE -eq 0 ]]; then
  echo
  echo "== Instruments recording skipped (--no-trace)"
  exit 0
fi

# Retries a traced run: the scenario aborts probabilistically on current main
# (see the crash finding in docs/Performance.md), and a lost trace is a lost
# recording, not a measurement to average.
record_trace() {
  local template="$1" name="$2" attempt attempts=3
  for ((attempt = 1; attempt <= attempts; attempt++)); do
    if record_trace_once "$template" "$name" "$attempt"; then return 0; fi
    if (( attempt < attempts )); then
      echo "  attempt $attempt failed; retrying" >&2
    else
      echo "  attempt $attempt failed; giving up on $template" >&2
    fi
  done
  return 1
}

record_trace_once() {
  local template="$1" name="$2" trace="$OUT/$2.trace"
  rm -rf "$trace"
  echo "== xctrace record: $template (frames=$TRACE_FRAMES, attempt $3) -> $trace"
  rm -f "$OUT/$name-stdout.txt"
  xcrun xctrace record --template "$template" --output "$trace" --no-prompt \
    --time-limit "$TRACE_TIME_LIMIT" \
    --target-stdout "$OUT/$name-stdout.txt" \
    --launch -- "$BINARY" --scenario --frames "$TRACE_FRAMES" --warmup "$WARMUP" \
    >"$OUT/$name-record.log" 2>&1 &
  local recorder=$! waited=0 record_status=0
  while kill -0 "$recorder" 2>/dev/null; do
    if (( waited >= TRACE_WALL_LIMIT )); then
      echo "error: $template recording exceeded ${TRACE_WALL_LIMIT}s; killing it" >&2
      pkill -P "$recorder" 2>/dev/null || true
      kill "$recorder" 2>/dev/null || true
      sleep 3
      pkill -9 -P "$recorder" 2>/dev/null || true
      kill -9 "$recorder" 2>/dev/null || true
      wait "$recorder" 2>/dev/null || true
      return 1
    fi
    sleep 2
    waited=$((waited + 2))
  done
  wait "$recorder" || record_status=$?
  if [[ $record_status -ne 0 ]]; then
    echo "error: xctrace record failed for $template" >&2
    cat "$OUT/$name-record.log" >&2
    return 1
  fi
  if grep -q '\[Error\]' "$OUT/$name-record.log"; then
    echo "error: xctrace reported run issues for $template" >&2
    cat "$OUT/$name-record.log" >&2
    return 1
  fi
  # A recording that ended on the time limit with no scenario output means the
  # target never ran to completion — an empty trace, not a measurement.
  if ! grep -q '^BENCH' "$OUT/$name-stdout.txt" 2>/dev/null; then
    echo "error: the $template run produced no scenario output; the target did" >&2
    echo "       not complete under this template on this machine." >&2
    return 1
  fi
  xcrun xctrace export --input "$trace" --toc >"$OUT/$name-toc.xml" 2>/dev/null || true
  return 0
}

trace_status=0
record_trace "Time Profiler" time-profiler || trace_status=1
record_trace "Allocations" allocations || trace_status=1

echo
echo "traces and logs: $OUT"
echo "open with: open $OUT/time-profiler.trace"
exit "$trace_status"
