# Frame-path performance

Measurement precedes optimization here, and a claim without numbers is not a
claim. This page records the harness, the rules, and every measurement that
has justified a change.

## The harness

`gama-bench` (`Sources/GamaBench`) runs one fixed scenario so two invocations
are comparable:

- a fixed **80×24** render loop over a representative tree — nested stacks,
  borders, per-row style changes, focusable controls, and a background fill,
  so `presentDiff` sees many style runs and `forEachRun` sees many short runs
  rather than one long default one;
- a **160×48 ↔ 80×24** resize loop, painted and presented at each new extent
  so the forced full present a resize implies is inside the measurement;
- a deterministic key/pointer script, replayed identically every run, so
  frame *n* receives the same event on every run and on every machine.

```bash
unset TOOLCHAINS
swiftly run swift build -c release --scratch-path /private/tmp/gama-bench-spm --product gama-bench
/private/tmp/gama-bench-spm/release/gama-bench            # 5 runs x 2000 frames, 200 warm-up
/private/tmp/gama-bench-spm/release/gama-bench --runs 3 --frames 500
```

Always measure a **release** build; a debug build's numbers describe the
debug build. Warm-up frames execute but are not recorded, because the first
frames pay for lazy metadata, first-touch pages, and buffer growth, and
folding that into the median flatters any later change.

`gama-bench` is **not a gate**. It asserts no threshold and is absent from
`scripts/check.sh`, so a loaded machine cannot fail a build with it.

### What it does not measure

Allocation **count** is deliberately absent rather than approximated. Nothing
available to a plain Darwin process counts allocations cumulatively —
`malloc_zone` statistics describe *live* blocks, not lifetime allocations — so
a number there would be invented. The harness reports peak resident bytes and
live-heap growth, both labeled as what they are. Allocation counts come from
Instruments' Allocations template.

## The native Apple host harness

`gama-bench` imports only GamaCore and GamaDraw, so it never touches the
paths Roadmap Task 5 names: CoreGraphics replay, font selection, attributed
string creation, and dirty-rect handling all live in
`Sources/GamaAppleUI/GamaHostView.swift`. `gama-apple-demo --scenario`
(`Sources/GamaAppleDemo/Scenario.swift`) closes that gap by replaying
`gama-bench`'s scenario through the *native* host:

- the same 80×24 tree — nested stacks, borders, per-row style changes,
  focusable controls, a background fill;
- the same eight-event key/pointer script, wrapped modulo its length, so
  frame *n* receives the same event on every run. Every button in the
  scenario tree is a no-op, which is what makes `.enter` and a pointer press
  safe to replay thousands of times;
- the same 80×24 ↔ 160×48 resize loop, redrawn at each new extent.

It boots `NSApplication` offscreen — accessory activation policy,
`finishLaunching()` without entering the event loop — hosts the primary scene
through the same `GamaShellCoordinator` the shell uses, and rasterizes every
frame through `GamaHostView.draw(_:)` via `cacheDisplay(in:to:)`. No run loop
means no timers, no user input, and no display-link pacing: every frame is
driven synchronously, which is what makes the measurement reproducible.

`scripts/profile-apple-host.sh` drives it:

```bash
unset TOOLCHAINS
./scripts/profile-apple-host.sh                  # 5 bare runs + both traces
./scripts/profile-apple-host.sh --no-trace       # bare runs only
./scripts/profile-apple-host.sh --runs 3 --frames 100 --out /private/tmp/x
```

It builds release into a scratch path outside the iCloud checkout, runs the
scenario N times bare, aggregates the per-phase medians, and then records a
Time Profiler and an Allocations trace with `xcrun xctrace record` — the
Allocations template does not currently work on this machine, which the
script reports as a failure rather than as an empty result; see the
measurement below. Bare and
traced numbers are never mixed: recording under Instruments perturbs timing,
so a traced run is evidence about *where* time goes, never about how much.
Like `gama-bench` it is **not a gate** — it asserts no threshold and is absent
from `scripts/check.sh`.

Determinism is reported rather than claimed. Every run prints two FNV-1a
digests computed outside every timed region — one over each frame's
draw-command count, one over the final rasterized bitmap — so two runs are
compared byte-for-byte instead of trusted. The script prints whether they were
identical across runs.

### What the Apple-host scenario does not measure

- **It is offscreen.** The window is created but never ordered front, and
  frames are rasterized through `cacheDisplay(in:to:)` rather than presented.
  Backing scale is the window's (2.0 here), so glyph rasterization is at the
  realistic scale, but compositing, surface handoff, and vsync are absent.
- **`draw(_:)` ignores its `dirtyRect`** — it repaints the full bounds on
  every call. So "dirty-rect handling" has no distinct measurable path today.
  That is a finding about the host, not a gap in the harness.
- **Core Animation and hangs/hitches templates are out of scope.** Both need
  an onscreen, run-loop-driven window; the roadmap names them, and they remain
  unmeasured rather than approximated.
- **Each phase drains its own autorelease pool inside its own timed region.**
  There is no run loop here, so nothing else would drain one. A real app
  drains per event-loop cycle instead, which distributes the same cost
  differently.
- **Accessibility is dormant by design.** `GamaHostView` does no
  accessibility work until a client queries it, and nothing in the scenario
  does, so that cost is deliberately outside the numbers.
- The bitmap digest is same-machine, same-OS evidence. Glyph rasterization
  differs across OS versions and backing scale factors.

## Rules

Taken from the roadmap and not relaxed:

1. Record hypotheses separately from measurements.
2. Optimize only what a measurement identifies. A plausible hot spot is a
   hypothesis.
3. An optimization **claim** requires at least a 10% median improvement across
   five identical release runs, or the removal of a reproducible hitch.
4. Untargeted phases must be no worse than 5% relative to baseline.
5. Correctness gates stay green; a faster wrong frame is not an improvement.

## Measurements

### 2026-08-28 — native Apple host baseline (pre-split)

Baseline for Roadmap Task 5, captured **before** the six-way
`GamaAppleUI`/`GamaAppleShell` split so the split has something to be measured
against. Nothing was optimized here; this entry is measurement and one
diagnosed failure.

Conditions: commit `b01e606`, pinned `main-snapshot-2026-08-21`, release
build, `gama-apple-demo --scenario --frames 150 --warmup 30`, five bare runs
via `scripts/profile-apple-host.sh`. Monospaced cell 9×17 pt, raster
1440×816 px at backing scale 2.0, 32 draw commands in the final frame.
Median nanoseconds per iteration:

| Phase | Run 1 | Run 2 | Run 3 | Run 4 | Run 5 |
| --- | --- | --- | --- | --- | --- |
| event + pump (`FrameHost` → `DrawList.from`) | 92,125 | 87,708 | 81,250 | 80,542 | 84,416 |
| draw (CoreGraphics replay, 80×24) | 804,625 | 561,375 | 538,416 | 508,250 | 570,333 |
| resize (layout + pump + draw) | 5,505,333 | 6,836,500 | 3,973,833 | 4,622,916 | 6,075,042 |

Median of those medians: event + pump 84,416 ns; draw 561,375 ns; resize
5,505,333 ns. Peak resident 69,280–69,648 KiB; live-heap growth
713,504–773,920 bytes. Run 1 is the cold outlier and is kept in the table
rather than dropped. The resize phase carries only seven samples per run, so
its 52% spread across runs is thin sampling as much as machine noise; the
event + pump phase, with 150 samples per run, spreads 13.7%.

**The scenario is deterministic and that is checked, not asserted.** All five
bare runs and the Time Profiler run printed the same two digests:
frame `0xa941fc78dc2f96a5`, bitmap `0x064d490591e51668`.

**Drawing dominates the native host by roughly 6.7×.** The whole
GamaCore/GamaDraw side of a frame — pump, layout, paint, `DrawList.from` —
is 84 µs; rasterizing that draw list through CoreGraphics is 561 µs. That
84 µs also cross-checks against the portable harness, which measures the same
tree's paint phase at ~37 µs and `forEachRun`/`DrawList.from` at ~43 µs after
the optimization below — 80 µs for the same work, measured through a
different harness. Further work on the portable frame path is optimizing the
small half.

Time Profiler attribution (one recording, 150 frames, 285 ms of samples at
1 ms; whole-process inclusive, so it includes launch and dyld):

| Frames present anywhere in the stack | Inclusive |
| --- | --- |
| CoreText | 24.9% |
| `NSStringDrawing` / typesetting | 21.1% |
| font lookup (`monospacedSystemFont`, `NSFont`) | 12.3% |
| attributed-string creation | 11.2% |
| `CellPainter` / pump | 8.1% |
| `DrawList.from` | 3.2% |

Those rows nest — font lookup and attributed-string creation both feed
CoreText — so they do not sum. Read as a ranking rather than a partition:
text is the cost, and font and attribute work are a substantial share of it.
The trace is regenerated by `scripts/profile-apple-host.sh`; `.trace` bundles
are not committed.

#### Per-command font creation aborts the host

Not a hypothesis. `GamaHostView.styledFont(for:)` calls
`PlatformFont.monospacedSystemFont(ofSize:weight:)` once **per text command
per frame** and caches nothing. Driven hard, that intermittently produces an
`NSFont` instance CoreText cannot resolve: `TAttributes::ApplyFont` inserts a
nil into the attribute dictionary and the process aborts with
`NSInvalidArgumentException` from
`-[__NSPlaceholderDictionary initWithObjects:forKeys:count:]`, under
`GamaHostView.draw(_:)` → `__NSStringDrawingEngine` →
`CTLineCreateWithAttributedString`.

Measured on this machine (macOS 27.0 26A5421a, Xcode 27.0 beta): at 150
frames the scenario aborted 7 times across the 12 attempts it took to collect
5 completed runs. Across 15 attempts at 500, 1000, 1500, 2000, and 2500
frames, exactly one completed.
It reproduces through `cacheDisplay(in:to:)` and through a direct
`draw(_:)` into a private `CGContext` alike, so it is not AppKit's display
path. A diagnostic build — the only change being a four-entry font cache
keyed on the bold/italic attributes — completed 5×2000 frames without a
single abort.

Two consequences, kept separate:

- **Measurement.** The roadmap's 2000-frame convention cannot be met on
  current `main`, which is why this baseline is 150 frames.
  `scripts/profile-apple-host.sh` retries an aborted run and reports the
  discarded count rather than hiding it; an aborted run yields no samples at
  all, so discarding it selects nothing about timing.
- **Fix.** Caching the four possible fonts belongs in its own PR with a
  regression test, not in this measurement slice. It is a correctness fix
  that happens to touch a path Task 5 also wants to optimize; the trace above
  already justifies looking there, and this abort is the stronger argument.
  Its effect on the draw median is **not** measured here — the diagnostic
  build was built to answer "does the abort stop", not "what does it cost" —
  so that PR must re-baseline with this same harness, and the split is then
  judged against the new numbers, not these.

#### Instruments Allocations could not be recorded

`xcrun xctrace record --template 'Allocations'` does not produce a usable
recording on this machine. The launched target deadlocks in
`liboainject.dylib`'s image initializer, in a `usleep` loop, **before `main`
runs** — sampled and confirmed: the whole main-thread stack is
`dyld4::APIs::runAllInitializersForMain` → `liboainject.dylib` → `usleep` →
`__semwait_signal`, with the recorder and the target both at 0% CPU after
eleven minutes. No Gama code executes. Time Profiler records the same binary
without incident.

The script therefore bounds every recording with `--time-limit` and treats a
recording whose target produced no scenario output as a failure rather than
as an empty result. **Allocation counts are consequently unmeasured**, and
`gama-bench`'s standing rule applies: nothing available to a plain Darwin
process counts allocations cumulatively, so no number is invented here. Task
5's "allocations no worse than 5%" criterion cannot be evaluated on this
machine until the Allocations template works; peak resident and live-heap
growth, both recorded above, are what exists.

### 2026-08-28 — `forEachRun` / `DrawList.from`

Baseline, three consecutive release runs of 5×2000 frames on the pinned
`main-snapshot-2026-08-21` (median ns per iteration):

| Phase | Run 1 | Run 2 | Run 3 |
| --- | --- | --- | --- |
| paint (pump + clearBack + CellPainter) | 35,417 | 33,375 | 33,542 |
| forEachRun via `DrawList.from` | 89,208 | 82,667 | 83,417 |
| presentDiff (ANSI diff) | 7,542 | 7,292 | 7,292 |
| resize loop (painted) | 218,958 | 206,208 | 206,834 |

Peak resident 8,928 KiB; live-heap growth 586,720 bytes.

**The measurement contradicted the ledger item's own ordering.** Roadmap Task
4.2 item 6 names `presentDiff` first, but `presentDiff` is the *cheapest*
phase measured — 7.3 µs — while the `forEachRun` → `DrawList.from` path costs
83 µs, 2.5× the entire paint phase and 11× `presentDiff`. Effort followed the
measurement.

Two changes, both behavior-preserving:

- **`CellBuffer.forEachRun`** finds a run's extent before building its text.
  The break condition only ever examined `style`, so splitting the two passes
  cannot move a run boundary — but it lets the string reserve its final
  capacity once instead of growing as it appends. The row base index is also
  hoisted out of the inner loop.
- **`DrawList.from`** makes one pass instead of three. It used to run
  `allSatisfy`, then `prefix(while:)`, then
  `reversed().drop(while:).reversed()` — walking each run up to three times and
  materializing two reversed collections before the final `String`. Locating
  the first and last non-space index directly answers all three questions:
  blankness is "no first index", the leading count is the column offset, and
  the slice between them is the visible text.

Result, five alternating baseline/optimized release runs (median ns):

| Pair | `forEachRun` baseline | `forEachRun` optimized | Change |
| --- | --- | --- | --- |
| 1 | 170,458 | 81,250 | −52.3% |
| 2 | 167,833 | 80,958 | −51.8% |
| 3 | 149,750 | 43,625 | −70.9% |
| 4 | 90,834 | 43,125 | −52.5% |
| 5 | 91,291 | 43,042 | −52.9% |

Pairs 1–3 ran against a loaded machine, which is why their absolute numbers
are high; the *ratio* is stable across load, and pairs 4–5 are the quiet
measurement. Untargeted phases in those quiet pairs: paint 36,583/37,416 →
36,750/37,583 (+0.4%), `presentDiff` 8,167/7,958 → 8,292/8,291 (+1.5%/+4.2%),
resize 231,542/224,958 → 233,042/232,583 (+0.6%/+3.4%) — all inside the 5%
band, and all noise rather than change, since neither edit is on those paths.

**`presentDiff` was deliberately left alone.** At 7.3 µs it is roughly 6% of
the frame path; even a large relative win there would be invisible, and the
rules above forbid optimizing a path no measurement identified. Its
`sgr(for:)` allocating a `[String]` per style change is a recorded
*hypothesis*, not a finding.
