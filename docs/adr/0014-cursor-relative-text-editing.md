# 0014 — TextField edits relative to a cursor; arrow keys reach the focused node first

Status: Accepted.

Records the first slice of text-input work: `TextField` gains a cursor and
a selection model, which changes two behaviors that had been settled since
the control was introduced. The layout, paint, and accessibility paths are
untouched.

## Context

`TextField` in `../../Sources/GamaCore/Primitives.swift` was append-only.
Its key handler appended on `.character`, removed the *last* character on
`.backspace`, and cleared the entire field on `.delete`; its doc comment
said outright that there was no cursor movement. That is a defensible
starting point for a control that only has to collect a short string, but
it forecloses everything above it: IME composition, bidirectional text, a
terminal text editor, and any serious editing story all need an insertion
point before they can even be represented.

Two facts about the surrounding code shaped the design.

`Character` in Swift is already one extended grapheme cluster. A cursor
expressed as a `Character`-count offset therefore cannot split a combining
sequence or a multi-scalar emoji, with no width table involved.
`TextLayout` in `../../Sources/GamaCore/TextLayout.swift` measures *display
columns*, which is a different question — it answers how wide a cluster
draws, not where an edit may land — so it is not a dependency of the edit
model and remains reserved for a future visual-caret slice.

`FrameHost.handle` in `../../Sources/GamaCore/FrameHost.swift` dispatched
`.up`/`.down`/`.left`/`.right` straight to spatial focus navigation, ahead
of the generic case that offers a key to the focused node's own handler.
That ordering is correct while no control wants arrow keys, and wrong the
moment one does. It could not simply be relaxed by having `TextField`
decline the key at a text boundary, because `moveFocusSpatially` falls back
to tab-order traversal when it finds no neighbour — so a declined `.left`
at offset zero would eject focus out of the field mid-edit rather than do
nothing.

## Decision

**Cursor offsets are `Character` counts.** `Selection` (anchor plus head,
in `../../Sources/GamaCore/TextEditing.swift`) carries either a collapsed
caret or a range. It is internal: nothing outside `GamaCore` needs it yet,
`TextField`'s public surface is unchanged, and keeping it internal costs
the doc-coverage gate nothing. Promoting it later is additive.

**Edits are cursor-relative, and `.delete` changes meaning.** `.character`
inserts at the caret; `.backspace` removes the cluster before it and
declines at offset zero; `.delete` removes the cluster *at* the caret and
declines at the end. The previous `.delete` behavior — clear the whole
field — is gone. Retaining it alongside a caret would be incoherent, every
backend maps both hardware Delete and Fn-Delete onto `.delete`, and no test
pinned the old behavior.

**Arrow keys offer the focused node first refusal.** The four hardcoded
cases in `FrameHost.handle` collapse into one that calls the focused node's
key handler first — after `stateStore.activate()`, matching the existing
Enter/Space path so a control rendered by more than one host writes to the
right one — and falls back to the same spatial navigation when the handler
declines or none is registered. `TextField` consumes `.left`/`.right`/
`.home`/`.end` unconditionally while focused and enabled, and deliberately
does not declare `.up`/`.down`, so vertical navigation is untouched while a
field has focus.

The blast radius of that dispatch change is one control: `TextField` is the
only caller of `registerKeyHandler` in the tree, and no backend intercepts
arrow keys before they reach the host, so every other focused node takes the
same path it always did.

## What this does not claim

There is no visual caret: cursor movement is proven by tests, not visible
in a running demo. There is no keyboard-driven selection — extending a
selection needs a modifier vocabulary that `Key` does not have, and adding
one touches every backend's decoder — and no click- or drag-to-select,
since pointer events fire only on press. There is no IME composition and no
bidirectional reordering. `Selection`'s range handling is written to be
correct for a future producer of non-collapsed selections, which is a seam,
not a feature. This adds no row to `../Capabilities.md`.

## Verification

`../../Tests/gamaTests/TextFieldCursorTests.swift` covers the edit
functions directly — insertion mid-string, replacement over a range,
declining at both boundaries, and a combining-cluster deletion that must
consume the whole cluster — and drives the rest through a real host. One
test discriminates the storage design specifically: typing, rebuilding,
moving to the start, rebuilding again, then typing must produce a character
at the front, which fails if the cursor lives in the view value instead of
host-owned storage. Two more pin the dispatch change from the other side:
vertical arrows still move focus away from a focused field, and horizontal
arrows still move focus between buttons.

`../../scripts/check-boundaries.sh` must stay green, since the new file
lives in a portable target and adds no imports, and
`../../scripts/check-apple.sh` must report its debug, test, and release
stages clean. Hosted proof is unavailable while the account billing lock
holds, so this record claims local verification only.

## Consequences

`TextField` now carries per-instance cursor state resolved against the
host, so it behaves like `@Reactive` storage: a field rebuilt every frame
keeps its caret. Callers that relied on `.delete` clearing a field must
select and replace instead. The arrow-key path gained one indirection for
every focused node, which is a dictionary lookup that already ran on the
generic key route. `TextLayout` stays where it is; the caret column it will
eventually need is a separate slice.
