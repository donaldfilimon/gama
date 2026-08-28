# MLIR Emitter Unification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Collapse the two duplicated MLIR walkers into one emitter so the structural and laid-out entry points cannot drift, and pin the emitted bytes so any future change is a reviewed decision.

**Architecture:** `Sources/GamaMLIR/Lowering.swift` currently has `emit` (structural, 14 cases) and `emitContainerLaid` (laid, 10 duplicated cases) with `emitLaid` as a 7-line dispatcher between them. Replace all three with one recursive `emit` taking an optional `Rect` and an optional `[LaidOutNode]`. Public signatures `lower(module:name:)` and `lower(laidOut:name:)` do not change.

**Tech Stack:** Swift 6.5-dev pinned snapshot `main-snapshot-2026-08-21`, Swift Testing only (no XCTest), SwiftPM.

**Spec:** `docs/superpowers/specs/2026-08-28-mlir-emitter-unification-design.md`

## Global Constraints

- Run `unset TOOLCHAINS` before every Swift command; invoke through `swiftly run swift …`. `swiftly run swift --version` must report `6.5-dev`.
- This checkout is iCloud/FileProvider-managed. Every `swift test` needs `--scratch-path /private/tmp/gama-framework-swiftpm`. Never run `git gc`, `git prune`, `git fsck`, or `git repack` here.
- Tests are Swift Testing only. Do not add `import XCTest`.
- `--filter` matches the source identifier, not the `@Suite` display name.
- `check-apple.sh` is the ONLY gate that runs `swift test`. Every test-level consequence of this work is invisible to the other twelve gates.
- Do not touch `.github/workflows/ci.yml`. The six required status-check contexts are name-pinned in ruleset 21626078; renaming a job orphans them and the branch can never merge (`bypass_actors: []`, `current_user_can_bypass: never`).
- Public API must not change. `check-doc-coverage.sh` fails on any undocumented public declaration.

---

## Spec corrections (measured 2026-08-28, recorded not absorbed)

The spec was written from source reading. Running the emitter falsified three of its statements. Per this repo's convention (see the wave-2 entry in `tasks/goals.md`, where two approved specs were corrected against reality and the corrections recorded), these are written down rather than silently fixed.

**1. The spec says "all fourteen through `lower(laidOut:)`". Not achievable via `LayoutEngine`.**
`LayoutEngine.layout` (`Sources/GamaCore/Layout.swift:205-209`) rewrites `.group(children:)` into `.overlay(alignment: .topLeading, children:)` before constructing the `LaidOutNode`. Feeding a `.group` through layout emits `gama.overlay`, never `gama.group`. The emitter's laid `group` branch is reachable only from a hand-built `LaidOutNode`. The plan therefore covers laid `group` with a hand-built node and states why.

**2. The `divider` structural/laid difference is NOT emitter duplication and must be PRESERVED.**
A nil-axis divider inside a stack has its `axis` materialized by `LayoutEngine.layoutStack` (`Layout.swift:311-318`). Structural omits `axis`; laid carries `axis = "v"`. That is a layout effect reaching the emitter through a different `RenderNode` value, not two walkers disagreeing. Unification must not "fix" it. A fixture pins both forms so a later refactor cannot erase the distinction by accident.

**3. `gama.empty` emits no attribute dict.**
`renderAttrs([])` returns `""`, so the structural form is exactly `"gama.empty"() : () -> ()`. Same for structural `gama.group`, whose close line is `}) : () -> ()`. A fixture written from source reading would have added `{}`.

Additionally measured, and now part of the pinned contract:
- `MLIRBuilder` indents exactly two spaces per level (`MLIR.swift:35-45`); `open()` writes then increments, `close()` decrements then writes.
- `MLIRBuilder.text` ends with exactly one `\n`.
- `MLIRAttr.escape` handles only `"`, `\`, newline, and tab. Everything else passes through raw.
- `.frame` and `.flexFrame` share the op name `gama.frame`. They are distinguishable only by attributes.

---

## File Structure

- `Sources/GamaMLIR/Lowering.swift` — modified. The three walkers become one. This is the only production file that changes in Tasks 1-2.
- `Tests/gamaTests/MLIRFixtureTests.swift` — created. Byte-exact fixtures, `@Suite("MLIR fixtures")`. Kept separate from the existing `@Suite("MLIR")` `contains` tests, which stay: they record intent (one exists to prove a `docs/Capabilities.md` claim) that byte pinning does not express.
- `docs/MLIRDialect.md` — modified in Task 3 only.

---

### Task 1: Pin the current bytes

Establishes the contract before anything moves. Every expected string below was captured by running the emitter at `72e80f6`, not reconstructed.

**Files:**
- Create: `Tests/gamaTests/MLIRFixtureTests.swift`

**Interfaces:**
- Consumes: `GamaLowering.lower(module:name:)` and `GamaLowering.lower(laidOut:name:)` from `GamaMLIR`; `RenderNode`, `LaidOutNode`, `LayoutEngine`, `Rect`, `Size`, `Alignment`, `TextStyle`, `Color`, `NodeID`, `EdgeInsets` from `GamaCore`.
- Produces: `MLIRFixtureTests` suite. Task 2 edits exactly two of its expectations and no others.

- [ ] **Step 1: Write the fixture file**

```swift
import Testing
@testable import GamaCore
@testable import GamaMLIR

/// Byte-exact lowering fixtures.
///
/// These pin the emitter's output, which nothing did before: the older
/// `MLIR` suite asserts with `contains`, and `check-mlir.sh` proves only that
/// `mlir-opt` accepts the text. Every expected string here was captured by
/// running the emitter, so a diff in this file is a real behavior change.
@Suite("MLIR fixtures")
struct MLIRFixtureTests {
    private static let frame = Rect(x: 0, y: 0, width: 20, height: 6)

    private func structural(_ node: RenderNode) -> String {
        GamaLowering.lower(module: node, name: "probe")
    }

    private func laid(_ node: RenderNode) -> String {
        GamaLowering.lower(laidOut: LayoutEngine.layout(node, in: Self.frame), name: "probe")
    }

    @Test("empty lowers with no attribute dict at all")
    func emptyHasNoAttributeDict() {
        // renderAttrs([]) returns "", so there is no `{}` — a fixture written
        // from source reading would have added one.
        #expect(structural(.empty) == """
        "gama.module"() ({
          "gama.empty"() : () -> ()
        }) {sym_name = "probe"} : () -> ()

        """)
    }

    @Test("text pins both color forms in one line")
    func textPinsBothColorForms() {
        let node = RenderNode.text(
            "Hi", style: TextStyle(foreground: .red, attributes: [.bold, .underline])
        )
        // fg is the concrete tensor form, bg is the "default" string form.
        // sgr 9 == bold(1) | underline(8).
        #expect(structural(node) == """
        "gama.module"() ({
          "gama.text"() {text = "Hi", fg = dense<[224, 64, 64]> : tensor<3xi8>, bg = "default", sgr = 9 : i64} : () -> ()
        }) {sym_name = "probe"} : () -> ()

        """)
    }

    @Test("string escaping covers exactly quote, backslash, newline, tab")
    func stringEscapingIsExactlyFourCharacters() {
        let node = RenderNode.text("q:\" b:\\ n:\n t:\t end", style: .plain)
        // The escapes stay on one physical line. MLIRAttr.escape handles only
        // these four; anything else passes through raw.
        #expect(structural(node) == #"""
        "gama.module"() ({
          "gama.text"() {text = "q:\" b:\\ n:\n t:\t end", fg = "default", bg = "default", sgr = 0 : i64} : () -> ()
        }) {sym_name = "probe"} : () -> ()

        """#)
    }

    @Test("a full 64-bit NodeID wraps negative through Int64(bitPattern:)")
    func nodeIDWrapsNegative() {
        // NodeID.root.raw is 14695981039346656037, above Int64.max.
        let node = RenderNode.interactive(
            id: NodeID.root, focusable: true, child: .text("x", style: .plain)
        )
        #expect(structural(node) == """
        "gama.module"() ({
          "gama.interactive"() ({
            "gama.text"() {text = "x", fg = "default", bg = "default", sgr = 0 : i64} : () -> ()
          }) {id = -3750763034362895579 : i64, focusable = true} : () -> ()
        }) {sym_name = "probe"} : () -> ()

        """)
    }

    @Test("flexFrame encodes an unbounded max as -1 and shares the gama.frame op")
    func flexFrameEncodesUnboundedAsNegativeOne() {
        let node = RenderNode.flexFrame(
            minWidth: 1, maxWidth: .max, minHeight: 2, maxHeight: 5,
            alignment: Alignment(horizontal: .trailing, vertical: .bottom),
            child: .text("x", style: .plain)
        )
        #expect(structural(node) == """
        "gama.module"() ({
          "gama.frame"() ({
            "gama.text"() {text = "x", fg = "default", bg = "default", sgr = 0 : i64} : () -> ()
          }) {min_width = 1 : i64, max_width = -1 : i64, min_height = 2 : i64, max_height = 5 : i64, halign = "trailing", valign = "bottom"} : () -> ()
        }) {sym_name = "probe"} : () -> ()

        """)
    }

    // MARK: - The divergence Task 2 resolves

    @Test("structural frame writes dimensions before alignment")
    func structuralFrameOrder() {
        #expect(structural(Self.frameNode) == """
        "gama.module"() ({
          "gama.frame"() ({
            "gama.text"() {text = "x", fg = "default", bg = "default", sgr = 0 : i64} : () -> ()
          }) {width = 10 : i64, height = 3 : i64, halign = "trailing", valign = "bottom"} : () -> ()
        }) {sym_name = "probe"} : () -> ()

        """)
    }

    @Test("laid frame writes alignment before dimensions — Task 2 changes this")
    func laidFrameOrder() {
        // THE ONE FIXTURE TASK 2 EDITS. Today the laid walker emits
        // halign/valign first; unification makes the structural order
        // canonical. Do not "fix" this expectation before Task 2.
        #expect(laid(Self.frameNode) == """
        "gama.module"() ({
          "gama.frame"() ({
            "gama.text"() {text = "x", fg = "default", bg = "default", sgr = 0 : i64, x = 19 : i64, y = 5 : i64, w = 1 : i64, h = 1 : i64} : () -> ()
          }) {halign = "trailing", valign = "bottom", width = 10 : i64, height = 3 : i64, x = 10 : i64, y = 3 : i64, w = 10 : i64, h = 3 : i64} : () -> ()
        }) {sym_name = "probe"} : () -> ()

        """)
    }

    private static let frameNode = RenderNode.frame(
        width: 10, height: 3,
        alignment: Alignment(horizontal: .trailing, vertical: .bottom),
        child: .text("x", style: .plain)
    )

    // MARK: - Differences that must SURVIVE unification

    @Test("a nil-axis divider gains its axis from layout, not from the emitter")
    func dividerAxisComesFromLayout() {
        // LayoutEngine.layoutStack materializes the axis (Layout.swift:311).
        // Structural and laid differ because the RenderNode differs, NOT
        // because two walkers disagree. Unification must preserve this.
        let node = RenderNode.stack(
            axis: .vertical, spacing: 0,
            alignment: Alignment(horizontal: .leading, vertical: .top),
            children: [.divider(style: .plain)]
        )
        #expect(structural(node).contains(
            #""gama.divider"() {fg = dense<[128, 128, 128]> : tensor<3xi8>} : () -> ()"#
        ))
        #expect(laid(node).contains(
            #"axis = "v", x = 0 : i64, y = 0 : i64, w = 20 : i64, h = 1 : i64"#
        ))
    }

    @Test("LayoutEngine never produces a laid gama.group")
    func layoutRewritesGroupToOverlay() {
        // Layout.swift:205 rewrites .group into .overlay(.topLeading), so the
        // emitter's laid group branch is unreachable through layout. Pinning
        // this stops a future reader from "fixing" the dead branch.
        let node = RenderNode.group(children: [.text("a", style: .plain)])
        #expect(structural(node).contains(#""gama.group"() ({"#))
        #expect(laid(node).contains(#""gama.overlay"() ({"#))
        #expect(!laid(node).contains(#""gama.group""#))
    }

    @Test("a hand-built laid group carries only the frame quad")
    func handBuiltLaidGroupCarriesOnlyFrame() {
        let child = RenderNode.text("a", style: .plain)
        let node = LaidOutNode(
            node: .group(children: [child]),
            frame: Rect(x: 1, y: 2, width: 20, height: 6),
            children: [LaidOutNode(node: child, frame: Rect(x: 1, y: 2, width: 1, height: 1))]
        )
        #expect(GamaLowering.lower(laidOut: node, name: "probe") == """
        "gama.module"() ({
          "gama.group"() ({
            "gama.text"() {text = "a", fg = "default", bg = "default", sgr = 0 : i64, x = 1 : i64, y = 2 : i64, w = 1 : i64, h = 1 : i64} : () -> ()
          }) {x = 1 : i64, y = 2 : i64, w = 20 : i64, h = 6 : i64} : () -> ()
        }) {sym_name = "probe"} : () -> ()

        """)
    }

    @Test("output ends with exactly one newline")
    func outputEndsWithExactlyOneNewline() {
        let text = structural(.text("x", style: .plain))
        #expect(text.hasSuffix("()\n"))
        #expect(!text.hasSuffix("\n\n"))
    }
}
```

- [ ] **Step 2: Run the suite to verify it passes on the UNMODIFIED emitter**

```bash
unset TOOLCHAINS
swiftly run swift test --scratch-path /private/tmp/gama-framework-swiftpm --filter MLIRFixtureTests
```

Expected: all tests PASS. If any fail, the captured bytes are wrong for this checkout — fix the fixture to match reality, do not change the emitter in this task.

- [ ] **Step 3: Commit**

```bash
git add Tests/gamaTests/MLIRFixtureTests.swift
git commit -m "test(mlir): pin the emitter's bytes before unifying it"
```

---

### Task 2: Unify the two walkers

**Files:**
- Modify: `Sources/GamaMLIR/Lowering.swift`
- Modify: `Tests/gamaTests/MLIRFixtureTests.swift` (exactly one expectation)

**Interfaces:**
- Consumes: Task 1's `MLIRFixtureTests`.
- Produces: `private static func emit(_ node: RenderNode, into b: inout MLIRBuilder, frame: Rect?, laid: [LaidOutNode]?)`. `emitLaid` and `emitContainerLaid` are deleted.

- [ ] **Step 1: Update the one fixture whose bytes legitimately move**

In `laidFrameOrder`, change the `gama.frame` close line to the structural order. Replace:

```
  }) {halign = "trailing", valign = "bottom", width = 10 : i64, height = 3 : i64, x = 10 : i64, y = 3 : i64, w = 10 : i64, h = 3 : i64} : () -> ()
```

with:

```
  }) {width = 10 : i64, height = 3 : i64, halign = "trailing", valign = "bottom", x = 10 : i64, y = 3 : i64, w = 10 : i64, h = 3 : i64} : () -> ()
```

Update the comment above it to say the order is now canonical.

- [ ] **Step 2: Run the suite to verify it FAILS**

```bash
unset TOOLCHAINS
swiftly run swift test --scratch-path /private/tmp/gama-framework-swiftpm --filter MLIRFixtureTests
```

Expected: `laidFrameOrder` FAILS; everything else passes. This is the red step — it proves the fixture actually observes the order.

- [ ] **Step 3: Replace the three walkers with one**

In `Sources/GamaMLIR/Lowering.swift`, delete `emitLaid` and `emitContainerLaid`. Change `emit`'s signature and add the two helpers:

```swift
/// The frame rectangle attached to every op on the laid-out path.
private static func frameAttrs(_ frame: Rect?) -> [(String, MLIRAttr)] {
    guard let f = frame else { return [] }
    return [
        ("x", .i64(f.minX)), ("y", .i64(f.minY)),
        ("w", .i64(f.size.width)), ("h", .i64(f.size.height)),
    ]
}

/// Emits a container's region, recursing over laid children when present and
/// structural children otherwise. Both entry points share this, so a case
/// cannot acquire different nesting on one path.
private static func region(
    _ op: String,
    _ attrs: [(String, MLIRAttr)],
    _ structuralChildren: [RenderNode],
    _ laid: [LaidOutNode]?,
    into b: inout MLIRBuilder,
    frame: Rect?
) {
    b.open("\"gama.\(op)\"() ({")
    if let laid {
        for c in laid { emit(c.node, into: &b, frame: c.frame, laid: c.children) }
    } else {
        for c in structuralChildren { emit(c, into: &b, frame: nil, laid: nil) }
    }
    b.close("})\(renderAttrs(attrs + frameAttrs(frame))) : () -> ()")
}
```

Rewrite each case to build its attributes once and call `region`. `.frame` keeps the structural order, which is now canonical for both paths:

```swift
case .frame(let w, let h, let alignment, let child):
    var attrs: [(String, MLIRAttr)] = []
    if let w { attrs.append(("width", .i64(w))) }
    if let h { attrs.append(("height", .i64(h))) }
    attrs.append(("halign", .str(name(alignment.horizontal))))
    attrs.append(("valign", .str(name(alignment.vertical))))
    region("frame", attrs, [child], laid, into: &b, frame: frame)
```

Both entry points must be updated. Keep the existing `= "main"` defaults —
dropping them is a source-breaking API change and `check-doc-coverage.sh`
will not catch it.

```swift
public static func lower(module node: RenderNode, name: String = "main") -> String {
    var b = MLIRBuilder()
    b.open("\"gama.module\"() ({")
    emit(node, into: &b, frame: nil, laid: nil)
    b.close("}) {sym_name = \(MLIRAttr.str(name).rendered)} : () -> ()")
    return b.text
}

public static func lower(laidOut root: LaidOutNode, name: String = "main") -> String {
    var b = MLIRBuilder()
    b.open("\"gama.module\"() ({")
    emit(root.node, into: &b, frame: root.frame, laid: root.children)
    b.close("}) {sym_name = \(MLIRAttr.str(name).rendered)} : () -> ()")
    return b.text
}
```

Note the asymmetry that makes the unified signature work: `emit`'s `laid`
parameter holds THIS node's laid children, so `lower(laidOut:)` seeds it with
`root.children` while `region` passes each child's own `c.children` down.

- [ ] **Step 4: Run the suite to verify it passes**

```bash
unset TOOLCHAINS
swiftly run swift test --scratch-path /private/tmp/gama-framework-swiftpm --filter MLIRFixtureTests
```

Expected: all PASS. Critically, every fixture OTHER than `laidFrameOrder` must pass **untouched**. If you had to edit a second expectation, the refactor changed behavior it was not supposed to — stop and find out why.

- [ ] **Step 5: Run the older MLIR suite and the dialect gate**

```bash
unset TOOLCHAINS
swiftly run swift test --scratch-path /private/tmp/gama-framework-swiftpm --filter MLIRTests
./scripts/check-mlir.sh
```

Expected: both pass. `check-mlir.sh` requires `mlir-opt` on `PATH`.

- [ ] **Step 6: Commit**

```bash
git add Sources/GamaMLIR/Lowering.swift Tests/gamaTests/MLIRFixtureTests.swift
git commit -m "refactor(mlir): one emitter for both entry points"
```

---

### Task 3: Reconcile the emitter and the dialect reference

**Files:**
- Modify: `Sources/GamaMLIR/Lowering.swift` (the `.divider` case)
- Modify: `Tests/gamaTests/MLIRFixtureTests.swift`
- Modify: `docs/MLIRDialect.md`

**Interfaces:**
- Consumes: the unified `emit` from Task 2.
- Produces: no API change.

- [ ] **Step 1: Write the failing fixture for the divider's new attributes**

Add to `MLIRFixtureTests`:

```swift
@Test("divider emits the full TextStyle like its sibling ops")
func dividerEmitsFullStyle() {
    // docs/MLIRDialect.md has always documented fg/bg/sgr. The node carries a
    // full TextStyle and gama.text and gama.styled both emit all three, so the
    // reference was right and the emitter was incomplete.
    let node = RenderNode.divider(
        style: TextStyle(foreground: .red, background: .blue, attributes: [.bold]),
        axis: .horizontal
    )
    #expect(structural(node) == """
    "gama.module"() ({
      "gama.divider"() {fg = dense<[224, 64, 64]> : tensor<3xi8>, bg = dense<[80, 128, 255]> : tensor<3xi8>, sgr = 1 : i64, axis = "h"} : () -> ()
    }) {sym_name = "probe"} : () -> ()

    """)
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
unset TOOLCHAINS
swiftly run swift test --scratch-path /private/tmp/gama-framework-swiftpm --filter dividerEmitsFullStyle
```

Expected: FAIL — actual output has `fg` and `axis` but no `bg` or `sgr`.

- [ ] **Step 3: Add bg and sgr to the divider case**

```swift
case .divider(let style, let axis):
    var attrs: [(String, MLIRAttr)] = [
        ("fg", .color(style.foreground)),
        ("bg", .color(style.background)),
        ("sgr", .i64(Int(style.attributes.rawValue))),
    ]
    if let axis {
        attrs.append(("axis", .str(axis == .horizontal ? "h" : "v")))
    }
    b.line("\"gama.divider\"()\(renderAttrs(attrs + frameAttrs(frame))) : () -> ()")
```

- [ ] **Step 4: Update the two existing divider fixtures**

`dividerAxisComesFromLayout` asserts on `#""gama.divider"() {fg = dense<[128, 128, 128]> : tensor<3xi8>} : () -> ()"#`. That string now gains `bg` and `sgr`. Change it to:

```swift
#expect(structural(node).contains(
    #""gama.divider"() {fg = dense<[128, 128, 128]> : tensor<3xi8>, bg = "default", sgr = 0 : i64} : () -> ()"#
))
```

The laid assertion in that test is unaffected — it matches on `axis` and the frame quad, neither of which moves.

- [ ] **Step 5: Run the full suite**

```bash
unset TOOLCHAINS
swiftly run swift test --scratch-path /private/tmp/gama-framework-swiftpm --filter MLIR
```

Expected: all PASS, both suites.

- [ ] **Step 6: Correct docs/MLIRDialect.md**

Four corrections. In the op table:

- Add a row: `| `gama.empty` | leaf | none |`
- Change the `gama.divider` row's Attributes to: `` `fg`, `bg`, `sgr`, `axis` (`"h"`/`"v"`, present only when the node carries one) ``
- Change the `gama.frame` row's Attributes to append: `` , plus `halign`, `valign` ``
- Under the table, add:

```markdown
`.frame` and `.flexFrame` share the `gama.frame` op; they are distinguished by
whether they carry `width`/`height` or the `min_*`/`max_*` set, not by op name.
Attribute order is part of the contract and is pinned by `MLIRFixtureTests`:
dimensions, then alignment, then the frame rectangle. A nil-axis divider inside
a stack gains its `axis` from `LayoutEngine`, so the frame-annotated lowering
can carry an `axis` the structural lowering does not — that is a layout effect,
not an emitter difference.
```

- [ ] **Step 7: Run the documentation gates**

```bash
unset TOOLCHAINS
./scripts/check-docs.sh && ./scripts/check-doc-coverage.sh
```

Expected: both exit 0.

- [ ] **Step 8: Commit**

```bash
git add Sources/GamaMLIR/Lowering.swift Tests/gamaTests/MLIRFixtureTests.swift docs/MLIRDialect.md
git commit -m "fix(mlir): emit the divider's full style, and correct the reference"
```

---

### Task 4: Full local gate run and ledger

**Files:**
- Modify: `tasks/todo.md`

- [ ] **Step 1: Run the gates this work touches**

```bash
unset TOOLCHAINS
./scripts/check-apple.sh && ./scripts/check-boundaries.sh && ./scripts/check-mlir.sh
```

Capture each exit code from the command itself — `cmd > log 2>&1; echo "EXIT: $?"`. A piped `tail` reports tail's status, not the command's, and has manufactured false green claims in this repo before.

- [ ] **Step 2: Flip Roadmap item 9**

In `tasks/todo.md`, change `- [ ] Item 9: MLIR emitter unification…` to `- [x]`, citing the PR, the fixture count, and the two byte changes (laid `gama.frame` order; divider `bg`/`sgr`). Record that `.group`'s laid branch is unreachable through `LayoutEngine` and that the divider axis difference is a layout effect deliberately preserved — those are the spec corrections and they belong in the permanent record.

- [ ] **Step 3: Commit and open the PR**

```bash
git add tasks/todo.md
git commit -m "docs(ledger): close Roadmap item 9"
git push -u origin HEAD
gh pr create --base main --title "refactor(mlir): unify the emitter and pin its bytes"
```

Merge only when all six hosted jobs are green at the exact head.
