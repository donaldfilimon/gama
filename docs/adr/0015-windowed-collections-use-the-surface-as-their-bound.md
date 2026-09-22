# 0015 — A windowed collection bounds itself by the surface, not by its own frame

Status: Accepted.

Records `VirtualizedList` and the `surfaceSize` environment value it reads.
Both `ForEach` and `IdentifiedForEach` keep compiling every element; this
record does not change them.

## Context

`ForEach` and `IdentifiedForEach` in `../../Sources/GamaCore/View.swift`
map over `data.indices` and call `content(element).render(...)` for every
element on every build pass. For a menu that is right. For a collection
with thousands of rows it means the build cost scales with the data rather
than with what a viewer can see, and no amount of layout cleverness
recovers a cost already paid during the build.

The obstacle is ordering. A view compiles before layout runs, so at the
moment it must decide which rows to build it does not know what frame it
will receive — that is precisely what `LayoutEngine` computes afterwards
from the tree the build produced. A collection cannot ask "how tall am I"
without inverting the pipeline into build → layout → build.

`EnvironmentValues` carried no size at all, so a view could not even ask
how large the *surface* was.

## Decision

**`EnvironmentValues.surfaceSize` is the whole surface, and is documented
as an upper bound rather than a frame.** `FrameHost.pump` sets it beside
`focusedID` before each build. A view that reads it learns the most it
could ever display, never what it will actually get. Host-less rendering
leaves it `nil`, which every consumer must treat as "no viewport known."

**`VirtualizedList` windows against that bound and accepts being
conservative.** A list sharing a surface with a header builds a few rows
that layout will not place. The residual is bounded by the surface, so the
build stays screen-sized instead of collection-sized, which is the entire
point. Trading exactness for a single-pass build is the deliberate choice;
a measured viewport would require the two-pass inversion above.

**Rows are uniform height.** `rowHeight` defaults to one cell, and the
visible range is arithmetic on the scroll offset. Uniformity is what makes
windowing possible without measuring, and a collection of variably sized
rows is a different design rather than a parameter of this one.

**Identity comes from the element.** A row renders under `id(element)`,
exactly as `IdentifiedForEach` does, so `@Reactive` state and focus follow
a row as the window moves rather than being re-keyed by its position in
the window.

**Scroll keys are consumed at both ends.** The offset clamps, and the
handler still returns `true`. Declining would hand the key to spatial
navigation, whose no-neighbour fallback is tab order, so overshooting the
last row would eject focus out of the list. This is the same reasoning ADR
0014 applied to the text cursor, and it is why that record's dispatch
change is a prerequisite for this one: before it, a focused node could not
take an arrow key at all.

**Host-less rendering builds everything.** With no surface there is no
window, and `gama-demo --emit-mlir` and isolated `render(in:)` calls stay
total rather than silently emitting a partial tree.

## What this does not claim

This is not a `ScrollView`: there is no clipping, no nested scrolling, no
momentum, no scrollbar, and no pointer-wheel handling. It is not a `Table`
— there is still no such type. It does not virtualize `ForEach` or
`IdentifiedForEach`, which remain eager by design. Nothing here measures a
row, so a list whose rows are not `rowHeight` tall will window incorrectly;
that is a stated precondition, not a bug to be discovered. This adds no row
to `../Capabilities.md`.

## Verification

`../../Tests/gamaTests/VirtualizedListTests.swift` pins the load-bearing
claim directly — a thousand-row collection on a twelve-row surface builds
at most twelve rows and does not contain the nine-hundredth — plus window
movement under the arrow keys, clamping at both ends, element-derived row
identity, and the host-less fallback building every row.
`../../scripts/check-boundaries.sh` must stay green, since the new file
lives in a portable target and adds no imports, and
`../../scripts/check-doc-coverage.sh` must pass without an allowlist entry
for the new public surface. Hosted proof is unavailable while the account
billing lock holds, so this record claims local verification only.

## Consequences

`EnvironmentValues` gains a value whose meaning is easy to misread; its doc
comment says "surface, not your frame" because a future reader will
otherwise assume it is the latter. Applications choosing `VirtualizedList`
accept uniform rows in exchange for a build that no longer scales with the
collection. If measured viewports ever arrive, `surfaceSize` becomes the
conservative fallback rather than the only answer, and `VirtualizedList`
narrows its window without changing its API.
