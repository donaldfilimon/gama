# 0013 — Flex priority is per-axis; the axis-agnostic public property is advisory

Status: Provisional.

This record exists so the decision it describes can be made against a
written statement of the options rather than re-derived from source. It
becomes Accepted when one of the three decisions below is chosen; until
then nothing in the public API changes, and the layout solver's behavior
is not in question. It closes the "needs a decision record" half of the
`flexPriority` residual that `../../tasks/todo.md` has carried since the
2026-09-06 source review; the other half is the choice itself.

## Context

`RenderNode` exposes two answers to "does this node compete for stack
space", and they disagree by design:

- `public var flexPriority: FlexPriority` is axis-agnostic. A
  `flexFrame` reports `.flexible` when *either* `maxWidth` or `maxHeight`
  is `.max`; wrappers forward their child's answer; everything else is
  `.fixed`.
- `func flexPriority(along axis: Axis) -> FlexPriority` is internal and
  per-axis. The same `flexFrame` is flexible on `axis` only when *that
  axis'* maximum is `.max`, so a `maxWidth: .max` child of a `VStack`
  stays fixed-height and merely fills the width.

`318561e` ("resolve stack flexibility per axis") moved the stack solver in
`../../Sources/GamaCore/Layout.swift` onto the per-axis form at all three of
its call sites. Since then the public property has had no reader anywhere
in `Sources/`, `Tests/`, or `docs/` other than its own declaration in
`../../Sources/GamaCore/RenderNode.swift`; its doc comment already says its
answer is advisory. The public surface therefore still carries a name that
promises the solver's input while the solver consults something else.

Two constraints frame the choice. The framework is pre-release and has
already taken deliberate source breaks when a settled design made an old
shape misleading; `../SceneMigration.md` records the `App.content` removal
in exactly those terms. And every public declaration must carry a `///`
under the doc-coverage gate, so whichever form is public must document the
axis semantics honestly rather than by allowlist.

## Decision

Not yet made. The three coherent options, with the recommendation stated
so it can be argued against:

**A — promote the per-axis form; deprecate the axis-agnostic one.**
Make `flexPriority(along:)` public with its existing doc comment. Mark
`flexPriority` `@available(*, deprecated, message:)` pointing at the
per-axis form, and remove it in a later pre-release break recorded the way
`../SceneMigration.md` records `App.content`. Recommended: the public API
then says what the solver does, there are no internal callers to migrate,
and the deprecation window costs one attribute.

**B — keep the property as a documented convenience.** Leave it public and
unchanged (the either-axis reading), rewrite its doc comment to say
"flexible on at least one axis; not what layout consults", and add a test
pinning it equal to the disjunction of the two per-axis answers so the two
cannot drift apart silently. Breaks nothing. Leaves a public name that
means less than it reads.

**C — remove the property outright.** Pre-release permits it. Rejected as
the first move only because A reaches the same end state with a warning
period for any external caller.

## What this does not claim

No code changes ship with this record. Layout behavior is unchanged under
every option; the stack solver has been per-axis since `318561e` and the
layout suites pin that. This is not a capability claim and adds no row to
`../Capabilities.md`.

## Verification

For whichever option is chosen: `../../scripts/check-doc-coverage.sh` must
pass without an allowlist entry (a newly public declaration needs its
`///`); `../../scripts/check-boundaries.sh` must pass (`GamaCore` stays
stdlib-only, which none of the options threaten);
`../../Tests/gamaTests/LayoutTests.swift` and
`../../Tests/gamaTests/P1LayoutTests.swift` must keep passing unchanged,
since they pin the per-axis solver and none of the options touch it. Under
A, a compile of the deprecated property must produce the deprecation
warning and nothing else. Under B, the new disjunction test is the proof.

## Consequences

Under A, one `public` keyword, one deprecation attribute, and one later
removal; external callers of the old property get a warning naming its
replacement. Under B, nothing moves and a misleading name is documented
into honesty. Under C, an immediate source break with no warning period.
In all three, `Layout.swift` is untouched.
