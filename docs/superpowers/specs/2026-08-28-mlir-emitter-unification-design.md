# MLIR emitter unification

Status: Approved (2026-08-28). Supersedes nothing. Implementation continues in
PR #60; Roadmap Task 4.2 item 9 closes only after the final implementation head
has the authoritative local and hosted evidence.

## Problem

`Sources/GamaMLIR/Lowering.swift` lowers a `RenderNode` tree to the textual
`gama` dialect through two public entry points — `lower(module:name:)` for the
structural tree and `lower(laidOut:name:)` for the laid-out tree. Behind them
sit two independent walkers that each re-list the same ten container cases with
their own copy of the attribute tables:

- `emit(_:into:frame:)` (`:48–181`) — the structural walker, a fourteen-case
  switch over `RenderNode`, taking an optional `Rect` that it appends as
  `x`/`y`/`w`/`h`. Every recursive call passes `frame: nil`, so the parameter is
  non-nil only when `emitLaid` calls it for a leaf.
- `emitContainerLaid(_:into:)` (`:194–284`) — the laid walker, recursing over
  `laid.children` rather than structural children, with its own `region(_:_:)`
  helper and its own per-case attribute tables.

`emitLaid(_:into:)` (`:185–192`) is not a third emitter. It is a seven-line
dispatcher: leaves go to `emit(…, frame:)`, containers go to
`emitContainerLaid`.

The duplication has already produced silent divergence, and nothing in the
repository can detect it. `gama.frame` emits its attributes in different order
on the two paths — the structural walker writes
`width`/`height` before `halign`/`valign` (`:136–158`), the laid walker writes
`halign`/`valign` first (`:246–263`). Both then append `x`/`y`/`w`/`h`. This
changes two laid outputs: the fixed `.frame` case and the `.flexFrame` case,
which share the `gama.frame` op but have distinct dimension sets. Before Task 1,
the divergence was invisible because **no test asserted the emitter's output
bytes**. The `@Suite("MLIR")` tests use
`String.contains` (`Tests/gamaTests/gamaTests.swift:567–627`), and
`scripts/check-mlir.sh` pipes `gama-demo --emit-mlir` into `mlir-opt` and
discards stdout — it proves the output parses, not what it says.

Four further disagreements exist between the emitter and
`docs/MLIRDialect.md`, which that file declares to be "the canonical
reference":

1. `gama.divider` is documented as carrying `fg`, `bg`, `sgr` (`:26`). The
   emitter writes only `fg`, plus an undocumented optional `axis` (`:76–81`).
2. `gama.empty` is emitted (`:59`) but has no row in the op table.
3. `gama.frame` is documented with `width`/`height` or the
   `min_*`/`max_*` set. Both walkers also emit `halign` and `valign` on every
   frame op; the table has never mentioned them.
4. `gama.module` is documented with `name`, but the emitter writes `sym_name`.

## Goals

- One attribute table per `RenderNode` case, so the two entry points cannot
  drift again.
- The emitter's exact output pinned by tests, so any future byte change is a
  reviewed decision rather than an accident.
- `docs/MLIRDialect.md` and the emitter agree.

## Non-goals

- No change to either public signature. `lower(module:name:)` and
  `lower(laidOut:name:)` keep their names, parameters, and return type. This is
  an internal restructuring with three deliberate byte changes: two laid frame
  order corrections and the divider's new `bg`/`sgr` attributes.
- No new MLIR ops, no dialect semantics change, no `mlir-opt` version bump.
- Not a Swift MLIR frontend. `GamaMLIR` stays a deterministic textual emitter,
  per `docs/adr/0001-own-the-rendering.md` and the target's own charter.

## Design

### One emitter, frame optional

Collapse `emit` and `emitContainerLaid` into a single recursive emitter that
carries both the optional frame and the optional laid-out children:

```swift
private static func emit(
    _ node: RenderNode,
    into b: inout MLIRBuilder,
    frame: Rect?,          // nil on the structural path
    laid: [LaidOutNode]?   // nil on the structural path
)
```

`lower(module:)` passes `nil` for both. `lower(laidOut:)` passes the node's
frame and its laid children. The two paths differ only in what they hand the
emitter, never in what the emitter knows about an op. A case cannot acquire a
different attribute list on one path, because there is only one list.

Two small helpers keep the switch readable:

- `frameAttrs(_ frame: Rect?) -> [(String, MLIRAttr)]` returns the
  `x`/`y`/`w`/`h` pairs, or empty when `frame` is nil. It stays appended last,
  which both walkers already do (`:143` and `:206`), so no `x`/`y`/`w`/`h`
  position changes.
- `region(...)` emits laid children with their own frames and children when
  present, or the supplied structural children without frames otherwise.

`emitLaid` disappears; its leaf/container split is exactly the distinction the
unified switch already makes.

Two alternatives were considered and rejected. Keeping two walkers over a
shared attribute function is a smaller diff, but leaves the walkers free to
diverge in op name, nesting, or child order — only the attributes would be
pinned, and op nesting is precisely what a future edit is most likely to get
wrong. A table-driven design, describing each case as data both paths
interpret, gives the strongest guarantee and would let the fixtures be
generated from the same table, but it trades a very direct, readable switch for
indirection in a file whose whole job is to be auditable against a documented
grammar.

### Canonical attribute order

Unification forces two laid expectations to change for `gama.frame`. Note that
`.frame` and `.flexFrame` share that one op — there is no `gama.flex_frame`;
the two are distinguished by whether they carry `width`/`height` or the
`min_*`/`max_*` set (`:143`, `:156`, `:253`, `:263`). The single ordering
decision therefore changes both node cases. **The structural order is
canonical:** dimensions
first, then alignment, then the frame rectangle.

```
width  = 40 : i64        min_width  = 10 : i64
height = 12 : i64        max_width  = -1 : i64
halign = "leading"       min_height = 3  : i64
valign = "top"           max_height = -1 : i64
x, y, w, h               halign = "leading"
                         valign = "top"
                         x, y, w, h
```

This matches the declaration order of the cases themselves —
`.frame(w, h, alignment, child)` — so the emitter reads top to bottom against
the node it is lowering and stays directly auditable against `RenderNode` and
the dialect reference. The choice deliberately changes exactly two laid exact
expectations, `frameBytes` and `flexFrameBytes`; structural fixture bytes remain
unchanged.

Sorting attributes into a fixed order independent of the source was rejected:
it would change the bytes of every op on both paths rather than these two laid
ops, and it decouples emitted order from source order, making the emitter
harder to audit against `docs/MLIRDialect.md`.

### Resolving the emitter/documentation disagreements

Each divergence resolves on its own evidence rather than by a blanket "code
wins" or "docs win" rule.

**`gama.divider` gains `bg` and `sgr` — the documentation is right and the
emitter is incomplete.** `RenderNode.divider(style: TextStyle, axis:)`
(`Sources/GamaCore/RenderNode.swift:69`) carries a full `TextStyle`, and
`TextStyle` has `foreground`, `background`, and `attributes`
(`Sources/GamaCore/Style.swift:99–106`). The emitter reads only `.foreground`.
Both other `TextStyle`-carrying ops emit all three — `gama.text` (`:62–68`) and
`gama.styled` — so the divider is the outlier and the data it needs is already
in hand. Emit `bg` as a color and `sgr` as the raw attribute bitmask, in the
same order and encoding `gama.text` uses. This changes divider bytes on both
paths. A plain divider uses `TextStyle.plain`, so its foreground, background,
and raw SGR value are `"default"`, `"default"`, and `0`; its foreground is not
gray.

**`gama.divider`'s `axis` is added to the reference — the emitter is right.**
`axis` came from a shipped behavioral fix (a `Divider` inside an `HStack` paints
vertically); the reference was simply never updated. Add it to the table as
optional, present only when the node carries an axis.

**`gama.empty` gains a row — the emitter is right.** It is emitted at `:59` and
has no attributes beyond the optional frame rectangle.

**`gama.frame` gains `halign` and `valign` in the table — the emitter is
right.** Both walkers have always emitted them. This matters more than a
missing row: it is the attribute pair whose ordering this design makes
canonical, so the reference must name it to make the order reviewable.

**`gama.module` documents `sym_name` — the emitter is right.** Generic-form
module output already carries `sym_name`; the reference's `name` spelling is
stale.

### Testing

The fixtures create the first byte-level contract this emitter has had. Task 1
is published in PR #60 as 17 tests: fourteen case tests plus escaping, a
hand-built laid group, and the final-newline contract. Because three byte
changes are intended, they are reviewed explicitly: the two laid frame
expectations move in Task 2, and divider style bytes move in Task 3.

Expected output lives **inline in Swift source**, primarily as ordinary
multiline string literals (`"""…"""`), in
`Tests/gamaTests/MLIRFixtureTests.swift` under `@Suite("MLIR fixtures")`. The
escaping fixture alone uses a raw multiline literal (`#"""…"""#`), where that
form keeps the dialect's backslash escapes readable as the bytes it pins.

Loading fixtures from files was rejected. `resources:` plus `Bundle.module`
would add resource bundling to a test target that CI builds for macOS, Linux,
Windows, and WebAssembly, and reading via `#filePath` needs Foundation, which
`Tests/gamaTests` deliberately imports in only one file
(`PlatformServicesTests.swift`). Neither buys anything a string literal lacks.

Coverage:

- All fourteen `RenderNode` cases through `lower(module:)`.
- Laid bytes for all fourteen cases. Normal `.group` layout is intentionally
  observed as `gama.overlay(.topLeading)` because `LayoutEngine` rewrites it;
  a hand-built `LaidOutNode.group` separately pins the laid `gama.group` branch.
- Both `Color` renderings: `dense<[r, g, b]> : tensor<3xi8>` and `"default"`.
- String escaping for `"`, `\`, newline, and tab.
- A full 64-bit `NodeID` through `gama.interactive`, exercising
  `Int64(bitPattern:)`.
- `.flexFrame` unbounded encoding, where `.max` becomes `-1`, on both paths.
- Nesting and indentation, since `MLIRBuilder`'s layout is now part of the
  contract.
- A plain divider's `"default"` foreground and a nil-axis divider gaining its
  vertical axis from stack layout.

The existing `@Suite("MLIR")` `contains` tests stay. They are cheap, and they
record intent the fixtures do not — `groupSentinelLowersToGamaGroup` exists to
prove a `docs/Capabilities.md` claim, and that reason survives the byte
pinning.

`scripts/check-mlir.sh` is deliberately left as a parseability gate. Comparing
`gama-demo --emit-mlir` against a golden file was considered and rejected: the
demo's output tracks the demo's scene, so every unrelated demo edit would
rewrite the golden file, and the unit fixtures already pin the emitter with far
better case coverage.

### Gates

Focused development uses the fixture filter, aggregate MLIR filter,
`check-mlir.sh`, `check-docs.sh`, and `check-doc-coverage.sh`. Final local
acceptance is `scripts/check.sh`, whose thirteen fail-closed gates are Apple,
Apple platforms, boundaries, concurrency negatives, C ABI, Embedded, Linux,
WASM, Android, Android emulator, MLIR, DocC, and documentation coverage. The
roadmap does not close until that complete driver succeeds and all six
name-pinned hosted jobs are green at the cited PR head.

## Delivery

Expand the existing PR #60 branch; do not open a replacement PR or rewrite its
published history. The commit order is the argument: landing the unification
before the fixtures exist would destroy the evidence that it was
behavior-preserving.

1. **Pin current bytes.** Already published in PR #60: 17 tests covering all
   fourteen cases on both paths plus escaping, hand-built laid group behavior,
   and the final newline. Green on the unmodified emitter.
2. **Correct the execution contract.** Record the published coverage, both
   laid order changes, plain-divider default, group rewrite, authoritative
   13-gate matrix, and PR #60 delivery authority.
3. **Unify.** Collapse the three functions into one emitter. Update only the
   laid-path `gama.frame` fixtures — both the `width`/`height` and
   `min_*`/`max_*` variants — whose attribute order legitimately moves. Every
   other fixture must pass untouched; that is the proof the refactor changed
   nothing else.
4. **Reconcile emitter and reference.** Add one eighteenth full-style divider
   test, add `bg` and `sgr` to `gama.divider`, update every affected divider
   expectation, and correct `sym_name`, divider `axis`, `gama.empty`, frame
   alignment/order, and the group/layout distinctions in the reference.
5. **Prove and record.** Run the complete 13-gate local matrix, require the six
   hosted jobs on the exact implementation head, then add the ledger-only
   completion commit and require the hosted jobs again before merge.

A reviewer reading the unification commit in isolation should see a fixture
diff containing only frame ops. If it contains anything else, the refactor
changed behavior it was not supposed to.

## Risks

**The unified signature carries two notions of children.** A case that reads
`laid` when it should read structural children, or vice versa, produces wrong
nesting. Caught by the Task 1 fixtures, which pin nesting and indentation for
every container on both paths.

**Adding `bg`/`sgr` to `gama.divider` changes bytes on both paths at once.**
Isolated in the divider commit so its fixture diff is reviewable on its own,
and it touches only divider ops.

**`docs/MLIRDialect.md` drifts again.** This design does not add a mechanism
that forces the reference to track the emitter; it only makes them agree today.
Closing that loop permanently — generating the table from the emitter, or
asserting it — is out of scope and worth its own item if the drift recurs.

## Out of scope

Roadmap items 6, 7, and 8 (`presentDiff`/`forEachRun` allocation work,
`~Copyable` `CellBuffer`/`Terminal`, and the `StrictMemorySafety` /
`InternalImportsByDefault` adoption) are independent and land separately. None
touches `Sources/GamaMLIR`.
