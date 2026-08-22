# gama v1 TUI + Embedded-clean core

Date: 2026-08-20  
Status: accepted (v1 implemented; GUI/macros/MLIR remain Proposed)  
Repo: `/Users/donaldfilimon/gama`

## Goal

Ship a Swift 6.4 **framework** (not a full GUI/MLIR compiler) that:

1. Describes UIs as a retained `ViewNode` tree built with result builders.
2. Lays out and paints that tree into a cell grid.
3. Renders the grid as a real ANSI TUI on macOS.
4. Proves `GamaCore` compiles as **Embedded Swift** on the OSS snapshot toolchain present on this Mac.

The `gama` executable stays a CLI and grows a `demo` subcommand that runs a showcase TUI.

## Current vs Proposed

| Capability | Status | Proof |
|------------|--------|--------|
| Hello-world `gama` CLI | **Current** (pre-slice) | `swift run gama` prints `Hello, world!` |
| `GamaCore` view tree + layout + paint | **This slice** | `GamaCoreTests` virtual-grid screenshots |
| `GamaTUI` POSIX/ANSI backend | **This slice** | `GamaTUITests` key/ANSI parse; `gama demo` on a TTY |
| Embedded compile of `GamaCore` | **This slice** | `scripts/check-embedded.sh` produces `.o` |
| GUI / windowed UI | **Proposed** | Not in v1 |
| Swift compiler-plugin macros | **Proposed** | Result builders are the v1 DSL; they are not macros |
| MLIR / SwiftIR backend | **Proposed** | Not a UI renderer; out of v1 |
| MCU flash / on-device UI | **Proposed** | Compile gate only |
| Linux TUI CI | **Proposed** | POSIX code may work; unproven on this Mac |
| Windows console | **Proposed** | Out of v1 |

A green `./scripts/check.sh` does **not** prove Embedded. A green Embedded script does **not** prove a live TUI. Do not write **Current** in AGENTS/README for GUI, macros, MLIR, or MCU.

## Non-goals (v1)

- SwiftUI, `any View`, `@State`, `@Binding`, property-wrapper engines
- Compiler macros (`@attached` / `@freestanding`)
- MLIR dialects, XLA, GPU
- ScrollView, Tabs, Modal, Table, Slider, Menu, StatusBar
- Truecolor, image widgets, font rendering
- Accessibility beyond keyboard focus
- Windows console
- Non-allocating Embedded (no heap). v1 allows heap (`indirect` enum, `Array`, `String`)

## Toolchain

Two gates, two compilers. Mixing them in one command is a bug.

### Gate A — macOS TUI (Xcode 6.4)

```bash
unset TOOLCHAINS
./scripts/check.sh
# → /usr/bin/xcrun --toolchain default swift build && swift test
```

`Package.swift` stays `swift-tools-version: 6.4`. PATH `swift` is swiftly and must not be the TUI gate.

### Gate B — Embedded `GamaCore` (OSS snapshot)

Xcode 6.4 **cannot** load an Embedded stdlib (`unable to load standard library for target 'arm64-apple-none-macho'`). The 2026-08-11 development snapshot **can**. Verified 2026-08-20: an `indirect` `ViewNode`-shaped enum compiled to `.o`.

```bash
# scripts/check-embedded.sh
unset TOOLCHAINS
SNAP=/Users/donaldfilimon/Library/Developer/Toolchains/swift-DEVELOPMENT-SNAPSHOT-2026-08-11-a.xctoolchain
sources=$(find Sources/GamaCore -name '*.swift' | sort)
"$SNAP/usr/bin/swiftc" \
  -target arm64-apple-none-macho \
  -enable-experimental-feature Embedded \
  -wmo -parse-as-library \
  -Xfrontend -disable-objc-interop \
  -c $sources \
  -o "${TMPDIR:-/tmp}/GamaCore.embedded.o"
```

This is an explicit exception to “always Xcode”: Embedded stdlib exists only in the snapshot. Gate A remains Xcode.

If the snapshot is missing, the script fails. Do not skip, stub, or mark the goal `done`.

## Package layout

```
Package.swift
Sources/
  GamaCore/          # stdlib only; no Foundation, no POSIX
  GamaTUI/           # depends on GamaCore; Darwin termios + ANSI
  gama/              # ArgumentParser CLI; depends on GamaTUI
Tests/
  GamaCoreTests/
  GamaTUITests/
  gamaTests/
scripts/
  check.sh           # Gate A
  check-embedded.sh  # Gate B
```

Targets:

| Target | Type | Depends on | Embedded? |
|--------|------|------------|-----------|
| `GamaCore` | library | none | yes |
| `GamaTUI` | library | GamaCore | no |
| `gama` | executable | GamaTUI, ArgumentParser | no |
| `GamaCoreTests` | test | GamaCore | no |
| `GamaTUITests` | test | GamaTUI | no |
| `gamaTests` | test | gama | no |

`ApproachableConcurrency` stays on all targets. Language mode: Swift 6.

`GamaCore` must not `import Foundation`. Use `String`, `Array`, `Int`, `Unicode.Scalar` from the stdlib.

## Architecture

Each frame:

```
AppState
  → @ViewBuilder body → ViewNode
  → Layout.layout(node, in: Size) → LayoutBox
  → Paint.paint(box, into: CellGrid, focus:)
  → GamaTUI diffs previous CellGrid vs new, writes ANSI
```

Events:

```
TTY bytes → Event (key / mouse / resize)
  → Engine.handle → Action?
  → AppState.reduce(action) → new AppState
  → rebuild
```

Tests use a virtual `CellGrid` and never open a TTY. `gama demo` is the live path.

## View tree

```swift
public struct NodeID: Hashable, Sendable, ExpressibleByStringLiteral {
    public var raw: String
    public init(_ raw: String)
    public init(stringLiteral value: String)
}

public struct Size: Equatable, Sendable {
    public var width: Int
    public var height: Int
    public static let zero: Size
}

public struct Point: Equatable, Sendable {
    public var x: Int
    public var y: Int
}

public struct Rect: Equatable, Sendable {
    public var origin: Point
    public var size: Size
    public var minX: Int { origin.x }
    public var minY: Int { origin.y }
    public var maxX: Int { origin.x + size.width }
    public var maxY: Int { origin.y + size.height }
    public func contains(_ p: Point) -> Bool
}

public struct EdgeInsets: Equatable, Sendable {
    public var top: Int
    public var leading: Int
    public var bottom: Int
    public var trailing: Int
    public static let zero: EdgeInsets
}

public enum Axis: Equatable, Sendable { case horizontal, vertical }

public enum Alignment: Equatable, Sendable { case leading, center, trailing }

public struct Color: Equatable, Sendable {
    public var ansi256: UInt8?
    public static let `default`: Color
}

public struct TextStyle: Equatable, Sendable {
    public var foreground: Color
    public var background: Color
    public var bold: Bool
    public var underline: Bool
    public var inverse: Bool
    public static let plain: TextStyle
}

public enum ViewNode: Equatable, Sendable {
    case empty
    case text(String, TextStyle)
    case button(label: String, id: NodeID)
    case textField(text: String, placeholder: String, id: NodeID)
    case checkbox(label: String, checked: Bool, id: NodeID)
    case progress(Double) // stored already clamped to 0...1
    case divider(Axis)
    case spacer(minLength: Int)
    indirect case padding(EdgeInsets, ViewNode)
    indirect case frame(
        minWidth: Int?, maxWidth: Int?,
        minHeight: Int?, maxHeight: Int?,
        ViewNode
    )
    indirect case stack(axis: Axis, alignment: Alignment, spacing: Int, [ViewNode])
    indirect case overlay([ViewNode])
    indirect case list(id: NodeID, selected: Int, [ViewNode])
}
```

Interactive widgets require an explicit `NodeID`. Duplicate IDs in one tree are a programming error: focus and hit-test use the first match; tests assert uniqueness in the demo tree.

## Result builder DSL

`ViewBuilder` produces a `ViewList`, not a hidden `VStack`. Containers wrap the list.

```swift
public struct ViewList: Equatable, Sendable {
    public var nodes: [ViewNode]
}

@resultBuilder
public enum ViewBuilder {
    public static func buildBlock() -> ViewList
    public static func buildBlock(_ parts: ViewNode...) -> ViewList
    public static func buildOptional(_ part: ViewNode?) -> ViewList
    public static func buildEither(first: ViewNode) -> ViewList
    public static func buildEither(second: ViewNode) -> ViewList
    public static func buildArray(_ parts: [ViewNode]) -> ViewList
    public static func buildExpression(_ node: ViewNode) -> ViewNode
    public static func buildLimitedAvailability(_ list: ViewList) -> ViewList
}

public func Text(_ string: String, style: TextStyle = .plain) -> ViewNode
public func Button(_ label: String, id: NodeID) -> ViewNode
public func TextField(_ text: String, placeholder: String = "", id: NodeID) -> ViewNode
public func Checkbox(_ label: String, checked: Bool, id: NodeID) -> ViewNode
public func Progress(_ value: Double) -> ViewNode  // clamps
public func Divider(_ axis: Axis = .horizontal) -> ViewNode
public func Spacer(minLength: Int = 0) -> ViewNode

public func VStack(
    alignment: Alignment = .leading,
    spacing: Int = 0,
    @ViewBuilder content: () -> ViewList
) -> ViewNode

public func HStack(
    alignment: Alignment = .leading,
    spacing: Int = 0,
    @ViewBuilder content: () -> ViewList
) -> ViewNode

public func ZStack(@ViewBuilder content: () -> ViewList) -> ViewNode

public func Padding(_ insets: EdgeInsets, @ViewBuilder content: () -> ViewList) -> ViewNode
public func Padding(_ all: Int, @ViewBuilder content: () -> ViewList) -> ViewNode

public func Frame(
    minWidth: Int? = nil, maxWidth: Int? = nil,
    minHeight: Int? = nil, maxHeight: Int? = nil,
    @ViewBuilder content: () -> ViewList
) -> ViewNode

public func List(id: NodeID, selected: Int, @ViewBuilder content: () -> ViewList) -> ViewNode
```

Single-child containers (`Padding`, `Frame`) that receive a `ViewList` of one node wrap that node. A `ViewList` of several nodes is wrapped in a vertical stack (spacing 0, leading) so the container always has one child.

App owns state. No `@State`.

```swift
public enum Action: Equatable, Sendable {
    case tap(NodeID)
    case edit(NodeID, String)
    case toggle(NodeID)
    case select(NodeID, Int) // list row index
    case submit(NodeID)      // Enter on a text field
}
```

## Layout

Units are **cells**, not points.

Two passes:

1. **Measure** — given a proposed `Size`, return a desired `Size`.
2. **Place** — assign a `Rect` in parent coordinates.

```swift
public struct LayoutBox: Equatable, Sendable {
    public var node: ViewNode
    public var rect: Rect
    public var children: [LayoutBox]
}

public enum Layout {
    public static func layout(_ root: ViewNode, in proposed: Size) -> LayoutBox
}
```

Rules:

| Node | Measure | Place |
|------|---------|--------|
| `text` | display width × 1 line (no wrap in v1; clip at paint) | origin |
| `button` | `"[ label ]"` width × 1 | origin |
| `textField` | `placeholder` or `text` width, min 8, × 1 | origin; stretches to proposed width if larger |
| `checkbox` | `"[x] label"` or `"[ ] label"` × 1 | origin |
| `progress` | proposed width (min 3) × 1 | fill proposed width |
| `divider` horizontal | proposed width × 1 | origin |
| `divider` vertical | 1 × proposed height | origin |
| `spacer` | along-axis minLength, cross-axis 0; in a stack, absorbs leftover | leftover split equally among spacers |
| `padding` | child + insets; proposed shrinks by insets first | child inset |
| `frame` | clamp child size to min/max | child |
| `stack` vertical | width = max child width (capped by proposed); height = sum(heights)+spacing | pack from top; cross-axis alignment |
| `stack` horizontal | symmetric | pack from leading |
| `overlay` | max of children | every child is placed at the overlay origin (top-leading); no extra alignment in v1 |
| `list` | column of children; **clip** to proposed height (no ScrollView) | pack from top; rows that do not fit are omitted from `LayoutBox.children` |
| `empty` | 0×0 | origin |

Negative sizes clamp to 0. Proposed `Size` with 0 width or height still produces a box (may be empty).

### Display width

```swift
public enum DisplayWidth {
    public static func of(_ string: String) -> Int
    public static func of(_ scalar: Unicode.Scalar) -> Int
}
```

- Combining marks / U+0000...U+001F (except tab): 0
- Tab: 1
- Hangul, CJK ideographs, fullwidth forms: 2
- Everything else: 1

v1 does not implement the full East Asian Width table. Tests cover ASCII, a CJK sample (`"你好"` → 4), and a combining mark.

## Paint

```swift
public struct Cell: Equatable, Sendable {
    public var scalar: Unicode.Scalar
    public var style: TextStyle
    public static let blank: Cell  // space + .plain
}

public struct CellGrid: Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var cells: [Cell] // row-major, count == width * height
    public init(width: Int, height: Int, fill: Cell = .blank)
    public subscript(x: Int, y: Int) -> Cell
    public mutating func put(x: Int, y: Int, scalar: Unicode.Scalar, style: TextStyle)
    /// Newline-joined rows; trailing spaces stripped per line. No ANSI.
    public func snapshot() -> String
}

public enum Paint {
    public static func paint(_ box: LayoutBox, into grid: inout CellGrid, focus: NodeID?)
}
```

Paint clips to the grid. Out-of-bounds cells are dropped, not trapped.

Focus: the focused button/field/checkbox/list uses `inverse: true` (or underline if already inverse).

Widget glyphs:

- Button: `[ label ]`
- TextField: text, or dim placeholder if empty; trailing spaces to rect width
- Checkbox: `[x]` / `[ ]` then a space then label
- Progress: `[###---]` style, `#` fill proportional, min width 3
- Horizontal divider: `-` repeated
- Vertical divider: `|`

v1 live TUI uses these ASCII glyphs so a `CellGrid.snapshot()` equals what a TTY shows (minus ANSI). Box-drawing characters are a follow-on slice, not v1.

## Events and engine

```swift
public enum Key: Equatable, Sendable {
    case character(Character)
    case enter, tab, backTab, escape, backspace
    case up, down, left, right
    case ctrlC
}

public struct Mouse: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case press, release, drag }
    public var kind: Kind
    public var button: Int  // 0 left
    public var x: Int       // 0-based cell
    public var y: Int
}

public enum Event: Equatable, Sendable {
    case key(Key)
    case mouse(Mouse)
    case resize(Size)
}

public enum HitTest {
    public static func hit(_ box: LayoutBox, at point: Point) -> NodeID?
}

public enum FocusOrder {
    public static func focusableIDs(_ root: ViewNode) -> [NodeID]
}

public struct Engine: Sendable {
    public var root: ViewNode
    public var focus: NodeID?
    public var size: Size
    public init(root: ViewNode, size: Size)
    public mutating func setRoot(_ root: ViewNode)
    public mutating func handle(_ event: Event) -> Action?
}
```

Focusable kinds: `button`, `textField`, `checkbox`, `list`.

`Engine.handle`:

| Event | Behavior | Action |
|-------|----------|--------|
| `tab` | next focusable (wrap) | nil |
| `backTab` | previous | nil |
| `enter` / space on button | — | `.tap(id)` |
| `enter` / space on checkbox | — | `.toggle(id)` |
| `enter` on textField | — | `.submit(id)` |
| printable char / backspace on textField | Engine does not store strings; it derives `newText` from the current tree | `.edit(id, newText)` |
| up/down on list | read `selected` from that `list` node | `.select(id, clampedIndex)` |
| `mouse press` on button/checkbox/field/list | focus that id; activate like enter (list selects the clicked row) | matching Action |
| `mouse release` / `mouse drag` | ignore in v1 | nil |
| `resize` | store size | nil |
| `ctrlC` | — | nil (demo maps this to quit) |
| unknown key | ignore | nil |

`Engine` does not own app strings. For textField edits it computes `newText` from the current node's text plus the key (`setRoot` must have run with the latest tree first). If the focused id is missing after a rebuild, focus resets to the first focusable. `Engine.init` focuses the first focusable id, or nil if none.

List `selected` lives on the node so Engine and Paint both see it. The app still owns the source of truth: it passes `selected` in each rebuild. Demo paints a `>` prefix on the selected row.

## GamaTUI (host)

```swift
public struct KeyParser: Sendable {
    public init()
    public mutating func push(_ bytes: [UInt8]) -> [Event]
}

public enum ANSIDiff {
    public static func encode(old: CellGrid, new: CellGrid) -> String
}

public final class Terminal: @unchecked Sendable {
    public init()
    public func enterRawMode() throws
    public func restore()
    public func size() throws -> Size
    public func write(_ string: String) throws
    public func pollEvent() throws -> Event?
}
```

- `enterRawMode`: `tcgetattr` / `tcsetattr` (no echo, no canonical), hide cursor, optional SGR mouse (`\u{1b}[?1000h` and `\u{1b}[?1006h`), alt screen (`\u{1b}[?1049h`).
- `restore`: reverse all of the above. Must run on every exit path (defer in `demo`).
- `KeyParser`: CSI arrows, SGR mouse `\u{1b}[<b;x;yM/m`, CR, TAB, `\u{1b}[Z` back-tab, `0x7f` / `0x08` backspace, `0x03` ctrl-C, UTF-8 characters. Incomplete sequences stay buffered.
- `ANSIDiff`: move-to + SGR + characters; full redraw on size change.
- SIGWINCH: GamaTUI sets a flag; `pollEvent` emits `.resize`.
- Errors: thrown `TerminalError` (`notATTY`, `tcsetattrFailed`, `ioctlFailed`). Demo prints the error and exits 1.

No Foundation in GamaTUI if Darwin/Glibc + libc is enough. `Darwin` on Apple. Do not import AppKit/SwiftUI.

## CLI

```
gama              → help (ArgumentParser default)
gama demo         → run TUI showcase until q / Ctrl-C
gama --version    → version string "0.1.0"
```

`demo` body (app state owned by the executable):

- Title `gama demo`
- `TextField` name
- `Checkbox` "ready"
- `Progress` from name length / 16
- `List` of three rows
- `Button` "OK" and `Button` "Quit"
- Quit button or `q` / Ctrl-C leaves raw mode and exits 0

## Testing

TDD. No production code without a failing test first.

`GamaCoreTests` (virtual, no TTY):

- Display width: `"A"`=1, `"你好"`=4, combining mark does not add a cell
- `VStack` of two `Text`s: stacked heights, width = max
- `HStack` + `Spacer`: spacer eats leftover
- `Frame(maxWidth:)` clamps
- `Padding` grows measured size
- Progress clamp: `-1` paints empty, `2` paints full
- Builder: `VStack { Text("a"); Text("b") }` → stack of two texts
- Paint snapshot of a button, focused vs unfocused
- `Engine` tab moves focus; enter on button yields `.tap`
- Hit-test: click on button rect yields id; miss yields nil
- List clip: 5 rows in height 3 paints 3

`GamaTUITests`:

- `KeyParser` arrows, enter, ctrl-C, SGR mouse press
- `ANSIDiff` empty→one cell contains the scalar (and some CSI)

`gamaTests`:

- `--help` mentions `demo`
- `--version` prints `0.1.0`

Do not require a TTY in tests. Do not treat `demo` interactive run as the gate.

## Error handling

- Layout/paint: clamp, clip, no trap
- Progress out of range: clamp
- Duplicate IDs: first match; demo test forbids duplicates
- Terminal setup failure: message on stderr, exit 1, restore if anything was set
- SIGTERM: restore tty if `demo` installed a handler (v1: restore via `defer` and `atexit`-style cleanup on the `Terminal` destructor / `restore()`)

## File map (v1)

Keep files small and single-purpose.

```
Sources/GamaCore/Geometry.swift      # Size, Point, Rect, EdgeInsets, Axis, Alignment
Sources/GamaCore/Style.swift         # Color, TextStyle, Cell, CellGrid
Sources/GamaCore/DisplayWidth.swift
Sources/GamaCore/NodeID.swift
Sources/GamaCore/ViewNode.swift
Sources/GamaCore/ViewBuilder.swift   # ViewList, ViewBuilder, Text/Button/... factories
Sources/GamaCore/Layout.swift
Sources/GamaCore/Paint.swift
Sources/GamaCore/Events.swift        # Key, Mouse, Event, Action
Sources/GamaCore/Focus.swift         # FocusOrder, HitTest
Sources/GamaCore/Engine.swift

Sources/GamaTUI/KeyParser.swift
Sources/GamaTUI/ANSIDiff.swift
Sources/GamaTUI/Terminal.swift

Sources/gama/gama.swift              # ParsableCommand + Demo command
Sources/gama/DemoApp.swift           # state + body + reduce

Tests/GamaCoreTests/*.swift          # one suite file per area
Tests/GamaTUITests/*.swift
Tests/gamaTests/CLITests.swift
```

## Success criteria (slice done only if all hold)

1. `./scripts/check.sh` exits 0 on Xcode 6.4 (build + all tests).
2. `./scripts/check-embedded.sh` exits 0: `GamaCore` compiles Embedded to an object file with the snapshot recipe above.
3. `gama demo` on a real TTY: field, checkbox, list, buttons, tab focus, quit restores the shell.
4. AGENTS.md lists both gates and the Current/Proposed table. It does not claim GUI, macros, MLIR, or MCU.

## Follow-on slices (not this spec)

1. Compiler-plugin macros that expand to the same `ViewNode` factories (host-only).
2. Linux TUI CI.
3. GUI backend painting the same `CellGrid` or a pixel sibling.
4. MLIR as a compute/shader path — unrelated to widget layout unless a future spec says otherwise.

## Key decisions

1. **Two modules** — POSIX stays out of `GamaCore` so Embedded compile is meaningful.
2. **Retained `ViewNode` + result builders** — SwiftUI-shaped API without `any View`.
3. **App-owned state + `Action`** — no `@State` runtime.
4. **Heap OK** — `indirect` enum; not non-allocating Embedded.
5. **Two toolchains** — Xcode 6.4 for TUI; OSS snapshot for Embedded. Documented exception.
6. **ASCII glyphs in v1** — snapshots match the live TUI.
7. **Mouse in v1** — SGR click hit-test; keyboard still required.
8. **Macros / MLIR / GUI deferred** — one spec, one slice.
9. **`Terminal` is a class** — raw mode + restore on all paths; not a noncopyable struct in v1.
10. **List `selected` is on `ViewNode`** — Engine and Paint read it; the app still passes it in each rebuild.
