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
