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

### 2026-09-01 — `CellBuffer` / `Terminal` copyability investigation

This was a measurement-first review of the proposed `~Copyable` boundary,
not an implementation pass. The outcome is deliberately narrow:

- **Do not make `CellBuffer` noncopyable.** The representative frame path
  contains no executed buffer copies to remove, and the allocation history
  contains no cell-array copy stack.
- **Do not make another public ownership change for performance.** `Terminal`
  is already `~Copyable` as of `8b5d260`, for the unique-tty correctness
  argument in [ADR 0010](adr/0010-noncopyable-terminal-ownership.md). A
  retrospective release A/B found no material runtime or allocation win.
  Keeping that existing semantic contract is separate from claiming a
  performance optimization.

No production source or public API changed in this investigation.

#### Toolchain and workloads

Every build used the repository pin, with `TOOLCHAINS` unset:

```text
Apple Swift version 6.5-dev
Swift version 6.5-dev (swift-6.5-DEVELOPMENT-SNAPSHOT-2026-08-21-a)
Target: arm64-apple-macosx27.0.0
```

The existing release `gama-bench` scenario already exercises the relevant
`CellBuffer` lifecycle: paint into one persistent buffer, borrow it into
`DrawList.from`, emit an ANSI diff, and repeatedly resize 80×24 ↔ 160×48.
Three independent invocations of 5 runs × 2,000 frames produced 30,000
measured frames after warm-up:

| Phase | Run 1 median | Run 2 median | Run 3 median |
| --- | ---: | ---: | ---: |
| paint (`HostPump` + clear + `CellPainter`) | 31,708 ns | 32,083 ns | 31,625 ns |
| `forEachRun` via `DrawList.from` | 37,042 ns | 37,416 ns | 38,000 ns |
| `presentDiff` | 6,791 ns | 6,834 ns | 7,083 ns |
| painted resize loop | 210,958 ns | 211,584 ns | 208,833 ns |

Peak resident size was 7,904–7,936 KiB. Live-heap growth was
322,800–322,864 bytes; as elsewhere on this page, that is a live-byte delta,
not an allocation count.

A separate 40-frame run (10 warm-up frames) enabled full Darwin malloc stack
history and exported a graph through `leaks --atExit --fullStackHistory`.
`malloc_history -allByCount` found five allocation stack groups whose symbol
names included `CellBuffer`, totaling 128 bytes. All five were
`CellBuffer.presentDiff` → `sgr(for:)` string/protocol metadata. There were:

- zero `DrawList.from` allocation stacks;
- zero `CellBuffer` copy-named stacks; and
- zero `_ContiguousArray` copy, `copyArray`, or `copyContents` stacks reached
  from the buffer path.

Full stack logging perturbs execution, so its timing was discarded; it was
used only to attribute allocations.

#### Actual `CellBuffer` ownership sites

The source inventory and optimized SIL agree:

| Site | Source-level ownership | Pinned release SIL |
| --- | --- | --- |
| backend session/context storage | initialize once, then mutate the stored value | owned initialization followed by `@inout` access |
| `HostPump.advance(into:emit:)` | `inout` buffer; `borrowing` emitter | `@inout CellBuffer`; emitter receives `@guaranteed CellBuffer` |
| `CellPainter.paint(_:into:)` | `inout` | `@inout CellBuffer` |
| `DrawList.from(_:)` | read-only value parameter | `@guaranteed CellBuffer` |
| `cell`, `forEachRun`, equality, and hashing | read-only | `@guaranteed` / `@in_guaranteed` |
| initialization and test helpers returning a buffer | ownership transfer | `@owned` result, not duplication |

The optimized whole-module `GamaDraw` SIL contains no `copy_value` or
`copy_addr` of `CellBuffer`, and the release object has no branch to a
`CellBuffer` copy helper. Because the type is publicly `Copyable`, its ABI
still carries three copy value witnesses; they describe what an external
caller is allowed to do, but no in-repository frame path calls them. Making
the type `~Copyable` would therefore trade away public value semantics and
its `Hashable` conformance to remove unused capability, not measured frame
cost.

#### Retrospective `Terminal` A/B

`Terminal` was not still a proposal at the time of measurement. Commit
`8b5d260` had already changed both platform declarations to `~Copyable` for
single-owner restoration semantics. To separate that correctness decision
from performance, release builds of its parent `b01e606` (copyable) and
`8b5d260` (noncopyable) were compared. The only production-source difference
between those builds is the two declaration annotations.

The copyable object contained nine calls to an outlined `Terminal` copy
helper: one in renderer begin, one in renderer end, two in renderer event
polling, two on raw-mode-entry cleanup paths, one on checked exit, and two in
session destruction. It also emitted three copy value witnesses. These are
real compiler-generated copies even though the source contains no deliberate
second tty owner. The noncopyable object contains neither the copy-helper
calls nor the copy witnesses; its object footprint is 32,138 bytes versus
33,090 bytes (952 bytes smaller, including 888 bytes of text).

That code-size difference did not become a measured frame-path win. A small
release probe, compiled against each historical module and run inside a PTY,
called the public `TUIRenderer.nextEvent(timeoutMillis: 0)` path 100,000 times
per process. Six alternating runs, with order reversed every run, produced
these medians of per-process mean time:

| Build | Median time per event poll |
| --- | ---: |
| copyable `Terminal` (`b01e606`) | 6,725 ns |
| noncopyable `Terminal` (`8b5d260`) | 6,683 ns |
| change | −0.6% |

That is far below the 10% optimization threshold and smaller than ordinary
run-to-run spread. With full malloc stack history enabled for 5,000 polls,
both builds recorded exactly 113 allocation calls / 5,304 bytes across the
whole process, zero allocations attributed to `TUIRenderer.nextEvent`, and
the same 2,912 KiB peak physical footprint. The old helper copies therefore
amount to retain/release and copy-in/out bookkeeping in this workload, not
heap duplication.

No new committed benchmark was needed. `gama-bench` already expresses the
open `CellBuffer` performance question. The `Terminal` comparison is a
historical two-commit ABI A/B requiring a real PTY, not a standing frame
benchmark; adding it to the portable harness would couple that harness to a
platform terminal for a migration that is already complete on independent
correctness grounds.

#### Decision

The evidence does **not** justify a new or broader move-only migration.
`CellBuffer` stays copyable and hashable. Existing `Terminal: ~Copyable`
stays in place because two independent restorers are semantically invalid,
not because it materially improves per-frame speed or allocations. Any
future `CellBuffer` proposal must first exhibit an executed copy or
copy-triggered allocation in a representative profile and then clear the
same 10% / 5% rules above.

### 2026-09-02 — native Apple host rebaseline after the styled-font cache

This reruns the native-host scenario after `dc3f21b` made the four possible
bold/italic fonts persistent per `GamaHostView`. The measurement checkout was
local `main` at `613e3fa`; its production sources and package manifest were
identical to hosted `origin/main` at `1b24690` (the two local-only commits
changed repository/agent configuration, not the built product).

Every build used the repository pin, with `TOOLCHAINS` unset and release
scratch at `/private/tmp/gama-apple-rebaseline-20260902-build`:

```text
Apple Swift version 6.5-dev
Swift version 6.5-dev (swift-6.5-DEVELOPMENT-SNAPSHOT-2026-08-21-a)
Target: arm64-apple-macosx27.0.0
```

The machine ran macOS 27.0 (26A5425a) and Instruments 27.0 (27A5252f).
That is a later macOS build than the pre-split run's 26A5421a, so this is a
current-main acceptance comparison, not a single-change microbenchmark.

#### Strict comparison with the pre-split workload

Five bare release runs used the baseline's exact
`--frames 150 --warmup 30` workload. All five completed on their first
attempt: **zero aborts**. The frame digest
`0xa941fc78dc2f96a5` and bitmap digest `0x064d490591e51668`
were identical across the five runs and identical to the pre-split baseline.

Median nanoseconds per iteration:

| Phase | Run 1 | Run 2 | Run 3 | Run 4 | Run 5 | Median | vs. pre-split median |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| event + pump (`FrameHost` → `DrawList.from`) | 71,333 | 71,459 | 71,584 | 72,083 | 71,791 | 71,584 | −15.2% |
| draw (CoreGraphics replay, 80×24) | 313,667 | 313,292 | 312,625 | 313,000 | 313,708 | 313,292 | −44.2% |
| resize (layout + pump + draw) | 1,228,167 | 1,227,375 | 1,215,500 | 1,247,958 | 1,228,209 | 1,228,167 | −77.7% |

Peak resident size was 68,736–68,992 KiB, versus 69,280–69,648 KiB
pre-split. Live-heap growth was 526,592–533,168 bytes, versus
713,504–773,920 bytes pre-split. Both are the metrics the scenario actually
reports; live-heap growth is not an allocation count.

The present host is therefore no worse than the pre-split baseline on any
measured timing or resident-memory metric, and all three timing medians are
more than 10% lower. The comparison spans the Apple-host split, the font
cache, and other intervening `main` changes, however, so it does **not**
attribute the full improvement to `dc3f21b` alone. The zero-abort result and
the font-cache regression suite establish the cache's correctness boundary;
the table establishes only the performance of current `main` as a whole.

#### The 2,000-frame convention and Time Profiler

A second five-run pass used the standing long workload,
`--frames 2000 --warmup 200`. It also completed 5/5 runs with zero aborts
and identical digests across runs: frame `0xc52876f4641e7925`, bitmap
`0xc928d5ec9cb32dfc`. Across the five runs, the median of per-run medians was
71,292 ns for event + pump, 313,833 ns for draw, and 1,176,333 ns for resize.
Peak resident size was 68,912–69,024 KiB and live-heap growth was
628,448–628,528 bytes. These longer-run values agree with the strict
150-frame comparison rather than exposing a late-run regression.

Time Profiler then recorded the same 2,000-frame release binary. The target
exited 0 after 1.760 seconds, emitted the same two long-run digests, and
produced 841 ms of 1 ms CPU samples. Whole-process inclusive attribution:

| Frames present anywhere in the stack | Current `main` | Pre-split |
| --- | ---: | ---: |
| `GamaHostView.draw(_:)` | 68.1% | not recorded |
| `NSStringDrawing` / typesetting | 36.6% | 21.1% |
| CoreText | 16.9% | 24.9% |
| `CellPainter` / pump | 15.1% | 8.1% |
| attributed-string creation | 10.1% | 11.2% |
| `DrawList.from` | 7.0% | 3.2% |
| font lookup (`monospacedSystemFont`, `NSFont`) | 3.9% | 12.3% |

The rows nest and the two recordings have different durations, so percentage
points are a ranking, not additive phase timing. The font-lookup share is
8.4 percentage points lower after the cache, consistent with the cache
removing repeated lookup from the hot path. Text drawing remains the dominant
native-host cost; the larger relative shares for portable work do not
contradict its lower bare-run time because the CoreGraphics draw path became
much cheaper and changed the denominator.

#### Allocation counts remain unmeasured

The Allocations template still could not run the scenario. Three documented
workflow attempts each reached the 120-second recorder limit with
`Failed to attach to target process`; each target stdout file was empty, so
no Gama code reported even one scenario sample. The generated trace bundle is
therefore an Instruments failure artifact, not an allocation recording.

This pass did not obtain a target stack, so it does not freshly prove the
pre-split pass's `liboainject.dylib` initializer diagnosis. It proves the
narrower current fact: the Allocations template produced no usable run on
this machine. **Allocation counts remain explicitly unmeasured**, and the
roadmap's allocation-regression criterion remains unevaluated. No live-block,
resident-memory, or Time Profiler value is relabeled as an allocation count.

Raw run logs and uncommitted trace artifacts are under
`/private/tmp/gama-apple-rebaseline-20260902-{compare,full}`.

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
