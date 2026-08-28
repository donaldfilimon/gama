# MLIR Emitter Unification Implementation Plan

> **For agentic workers:** Execute each task in order. Preserve the red step,
> keep commits focused, and use the repository's external SwiftPM scratch path.

**Goal:** Collapse the duplicated structural and laid MLIR walkers into one
emitter, pin every `RenderNode` case byte-for-byte, and reconcile the emitter
with the canonical dialect reference.

**Architecture:** `Sources/GamaMLIR/Lowering.swift` currently has a structural
`emit`, a laid `emitContainerLaid`, and an `emitLaid` dispatcher. Replace the
three with one recursive `emit` that accepts an optional `Rect` and optional
laid children. The public `lower(module:name:)` and `lower(laidOut:name:)`
signatures and their `name: String = "main"` defaults do not change.

**Delivery authority:** Continue the published fixture branch and expand PR
#60. Do not open a second implementation PR, rewrite published history, or
promote the stale partial implementation worktree.

**Spec:** `docs/superpowers/specs/2026-08-28-mlir-emitter-unification-design.md`

## Global constraints

- Run `unset TOOLCHAINS` before Swift commands and invoke Swift through
  `swiftly run swift`. The pinned compiler must report Swift 6.5-dev.
- Every direct `swift test` uses
  `--scratch-path /private/tmp/gama-framework-swiftpm` because the canonical
  checkout is FileProvider-managed.
- Tests use Swift Testing only. Preserve the existing intent-level
  `MLIRTests` suite in `Tests/gamaTests/gamaTests.swift`.
- Do not change public API, `Package.swift`, `Package.resolved`, CI workflows,
  or required status-check names.
- Do not weaken, skip, or reorder the full acceptance gates. `scripts/check.sh`
  is the authoritative 13-gate driver.

## Corrected measured contract

The fixture contract comes from executing the emitter, not reconstructing its
output from source inspection.

- Task 1 is already published in PR #60 as one 17-test suite. Fourteen tests
  cover all fourteen `RenderNode` cases and pin both structural and laid bytes.
  The other three pin escaping, a hand-built laid group, and exactly one final
  newline.
- A normal `.group` passed through `LayoutEngine` becomes
  `.overlay(.topLeading)` and emits `gama.overlay`. The otherwise unreachable
  laid `gama.group` branch is pinned with a hand-built `LaidOutNode.group`.
- A nil-axis divider inside a vertical stack gains `axis = "v"` from
  `LayoutEngine`; that difference must survive unification. A plain divider's
  foreground is `"default"`, not gray.
- Attribute-free structural `gama.empty` and `gama.group` omit `{}`. Every
  laid op carries `x`, `y`, `w`, and `h`, and laid containers recurse through
  their laid children.
- `.frame` and `.flexFrame` both emit `gama.frame`. Their current laid
  attribute orders both diverge from their structural orders. Task 2 changes
  exactly two laid fixture expectations, one for fixed frame and one for flex
  frame.

## Task 1: Pin the current bytes (published)

`Tests/gamaTests/MLIRFixtureTests.swift` contains `@Suite("MLIR fixtures")`
with `@testable import GamaCore` and `@testable import GamaMLIR`. It uses the
common `Rect(x: 0, y: 0, width: 20, height: 6)` layout frame and helpers for
structural and `LayoutEngine`-produced lowering.

The 17 tests are:

1. `emptyBytes`
2. `textBytes`
3. `stackBytes`
4. `overlayBytes`
5. `groupBytes`
6. `spacerBytes`
7. `dividerBytes`
8. `paddingBytes`
9. `borderBytes`
10. `backgroundBytes`
11. `frameBytes`
12. `flexFrameBytes`
13. `styledBytes`
14. `interactiveBytes`
15. `stringEscapingBytes`
16. `handBuiltLaidGroupBytes`
17. `outputEndsWithExactlyOneNewline`

The suite pins two-space indentation, concrete and `"default"` colors, raw
`sgr`, signed `Int64(bitPattern:)` wrapping for `NodeID.root`, asymmetric
padding, rounded titled borders, unbounded flex-frame encoding, and recursive
laid geometry. Preserve it as the baseline for Tasks 2 and 3.

## Task 2: Unify structural and laid emission

**Files:**

- Modify `Sources/GamaMLIR/Lowering.swift`.
- Modify only the two laid order expectations in
  `Tests/gamaTests/MLIRFixtureTests.swift`.

### Red step

Change the laid close line in `frameBytes` from alignment-first to:

```text
width, height, halign, valign, x, y, w, h
```

Change the laid close line in `flexFrameBytes` from alignment-first to:

```text
min_width, max_width, min_height, max_height, halign, valign, x, y, w, h
```

Run:

```bash
unset TOOLCHAINS
swiftly run swift test \
  --scratch-path /private/tmp/gama-framework-swiftpm \
  --filter MLIRFixtureTests
```

Require exactly `frameBytes` and `flexFrameBytes` to fail while the other 15
tests pass. A third failure means the expected contract or edit is wrong.

### Production refactor

Replace the three walkers with:

```swift
private static func emit(
    _ node: RenderNode,
    into b: inout MLIRBuilder,
    frame: Rect?,
    laid: [LaidOutNode]?
)
```

Add two private helpers:

- `frameAttrs(_:)` returns `x`, `y`, `w`, `h`, or an empty list.
- `region(...)` emits laid children with their own frames and children when
  `laid` is non-nil; otherwise it emits the supplied structural children with
  no frames.

Seed structural lowering with `frame: nil, laid: nil`. Seed laid lowering with
`frame: root.frame, laid: root.children`. Define each op name, base attribute
list, and region recursion once. Append frame attributes last. Use structural
dimension ordering as canonical for both fixed and flex frame.

### Task 2 verification

```bash
unset TOOLCHAINS
swiftly run swift test \
  --scratch-path /private/tmp/gama-framework-swiftpm \
  --filter MLIRFixtureTests
swiftly run swift test \
  --scratch-path /private/tmp/gama-framework-swiftpm \
  --filter MLIR
PATH="/opt/homebrew/opt/llvm/bin:$PATH" ./scripts/check-mlir.sh
```

Require 17 fixture tests and 21 aggregate MLIR tests to pass. The fixture diff
for this task must contain exactly the two laid order changes. Commit as:

```text
refactor(mlir): one emitter for both entry points
```

## Task 3: Emit full divider style and reconcile the dialect

**Files:**

- Modify the unified divider case in `Sources/GamaMLIR/Lowering.swift`.
- Add one test and update all affected divider bytes in
  `Tests/gamaTests/MLIRFixtureTests.swift`.
- Reconcile `docs/MLIRDialect.md` and the emitter's vocabulary comment.

### Red step

Add one eighteenth test that pins both structural and laid bytes for a
horizontal divider with concrete red foreground, concrete blue background,
and bold. Require the exact attribute order:

```text
fg, bg, sgr, axis, x, y, w, h
```

Run only the new test and require failure because the current emitter omits
`bg` and `sgr`.

### Production and fixture changes

Change the divider's base attributes to `fg`, `bg`, and raw `sgr`. Append the
optional axis, then frame attributes. Update every divider occurrence in
`dividerBytes`:

- Explicit plain horizontal divider, structural and laid.
- Nil-axis divider in a vertical stack, structural and laid.

Plain style must emit `fg = "default", bg = "default", sgr = 0 : i64`.
Structural nil-axis output still omits `axis`; laid output still gains
`axis = "v"` from layout.

Correct the dialect reference so:

- `gama.module` documents `sym_name`.
- `gama.empty` is listed as an attribute-free leaf.
- `gama.divider` documents `fg`, `bg`, `sgr`, and optional `axis`.
- `gama.frame` documents dimensions plus `halign` and `valign`.
- `.frame` and `.flexFrame` are explicitly documented as sharing
  `gama.frame`, with canonical dimensions, alignment, frame-quad order.
- The normal group rewrite, hand-built laid group coverage, and layout-derived
  divider axis are explicit.

### Task 3 verification

```bash
unset TOOLCHAINS
swiftly run swift test \
  --scratch-path /private/tmp/gama-framework-swiftpm \
  --filter dividerEmitsFullStyle
swiftly run swift test \
  --scratch-path /private/tmp/gama-framework-swiftpm \
  --filter MLIRFixtureTests
swiftly run swift test \
  --scratch-path /private/tmp/gama-framework-swiftpm \
  --filter MLIR
PATH="/opt/homebrew/opt/llvm/bin:$PATH" ./scripts/check-mlir.sh
./scripts/check-docs.sh
./scripts/check-doc-coverage.sh
```

Require 18 fixture tests and 22 aggregate MLIR tests to pass. Commit as:

```text
fix(mlir): emit divider style and correct the dialect reference
```

## Task 4: Authoritative acceptance, ledger, and PR #60

1. Run `scripts/check.sh` with a unique external scratch/evidence root and the
   pinned Android/Swift/MLIR environment. Capture the command's unpiped exit
   status and complete log.
2. Require its thirteen fail-closed gates: Apple, Apple platforms, boundaries,
   concurrency negatives, C ABI, Embedded, Linux, WASM, Android, Android
   emulator, MLIR, DocC, and documentation coverage. Require the final marker
   `OK — complete local Gama Framework acceptance matrix`.
3. Push the focused commits normally to the existing
   `abbey/mlir-emitter-fixtures` branch. Retitle and update PR #60; do not open
   another PR or force-push.
4. Require all six name-pinned hosted jobs at the exact implementation head.
5. Only then update Roadmap Item 9 with the 18-fixture and 22-MLIR-test counts,
   the two laid ordering changes, the divider style change, the group/divider
   layout distinctions, the full local matrix, and hosted run evidence. State
   truthfully that merge is pending if it has not occurred.
6. Push the ledger-only commit and require the six hosted jobs again at the
   exact final head. Merge only when the PR is current with `main`, all required
   jobs are green, and relevant review threads are resolved.

Before each push and merge, fetch and inspect ancestry, the complete diff,
`git diff --check`, generated artifacts, and worktree status. If `origin/main`
advances without overlap, merge it into the published branch normally. Do not
rebase or force-push published history. Stop for overlapping changes rather
than auto-resolving them.

## Expected final contract

- 18 fixture tests in one Swift Testing suite.
- 22 tests matched by `--filter MLIR` across the fixture and existing suites.
- No public API, manifest, lockfile, dependency, or CI change.
- Exactly two laid frame-order changes and the deliberate divider `bg`/`sgr`
  addition.
- Exact local 13-gate and hosted-six evidence at the heads cited by the
  roadmap ledger.
