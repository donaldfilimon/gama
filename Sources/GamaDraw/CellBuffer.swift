//  CellBuffer.swift — GamaDraw
//  Double-buffered cell grid — the shared raster every backend paints
//  into. Terminals flush `presentDiff()` ANSI; GUI/DOM/embed hosts walk
//  `forEachRun` to vectorize cells into draw commands. Platform-free.

import GamaCore

/// One grid cell: a character, its style, and wide-glyph bookkeeping.
public struct Cell: Hashable, Sendable {
    /// The grapheme stored in this cell (continuation cells keep a space).
    public var character: Character
    /// The foreground/background/attribute styling applied to the cell.
    public var style: TextStyle
    /// The second grid column occupied by a wide grapheme stored immediately
    /// before this cell. Backends skip continuation cells when emitting text.
    public var isContinuation: Bool
    /// Creates a cell; defaults produce the blank cell.
    public init(
        character: Character = " ", style: TextStyle = .plain,
        isContinuation: Bool = false
    ) {
        self.character = character
        self.style = style
        self.isContinuation = isContinuation
    }
    /// The default empty cell every buffer starts from.
    public static let blank = Cell()
}

/// Double-buffered cell grid shared by every backend: paint into the back
/// plane, then diff against the front plane on presentation.
public struct CellBuffer: Hashable, Sendable {
    /// Defensive ceiling for dimensions received from untrusted hosts.
    public static let maximumCellCount = 16 * 1_024 * 1_024
    /// Current grid dimensions in cells.
    public private(set) var size: Size
    private var front: [Cell]
    private var back: [Cell]
    private var forceFull = true
    /// Whether ANSI output uses 24-bit color (`false` falls back to 256).
    public var trueColor: Bool = true

    /// Creates a buffer of `size` (normalized to the defensive ceiling).
    public init(size: Size) {
        let normalized = Self.normalized(size)
        self.size = normalized.size
        let n = normalized.count
        self.front = Array(repeating: .blank, count: n)
        self.back = Array(repeating: .blank, count: n)
    }

    /// Resizes both planes, clearing content and forcing a full present.
    public mutating func resize(_ newSize: Size) {
        let normalized = Self.normalized(newSize)
        size = normalized.size
        let n = normalized.count
        front = Array(repeating: .blank, count: n)
        back = Array(repeating: .blank, count: n)
        forceFull = true
    }

    /// Resizes only when `newSize` would actually change the grid.
    ///
    /// Every backend used to carry its own version of this check, and a
    /// naive `size != newSize` comparison is wrong: ``size`` holds the
    /// *normalized* extent, so a request above ``maximumCellCount`` never
    /// compares equal and would re-allocate — and force a full present —
    /// on every single frame. Normalizing before comparing keeps a clamped
    /// surface on the cheap ANSI diff instead.
    ///
    /// - Returns: `true` when the grid was actually resized.
    @discardableResult
    public mutating func resizeIfNeeded(_ newSize: Size) -> Bool {
        guard Self.normalized(newSize).size != size else { return false }
        resize(newSize)
        return true
    }

    /// Clears the back plane to blank cells before a paint pass.
    public mutating func clearBack() {
        for i in back.indices { back[i] = .blank }
    }

    @inline(__always)
    private func index(_ x: Int, _ y: Int) -> Int? {
        guard x >= 0, y >= 0, x < size.width, y < size.height else { return nil }
        return y * size.width + x
    }

    /// Writes one grapheme at `p`, reserving a continuation cell after a
    /// wide glyph; out-of-bounds writes are ignored.
    public mutating func put(_ ch: Character, at p: Point, style: TextStyle) {
        guard let i = index(p.x, p.y) else { return }
        clearGlyph(overlapping: i)
        let width = TextLayout.cellWidth(of: ch)
        guard width > 0 else { return }
        if width == 2, index(p.x + 1, p.y) == nil { return }
        back[i] = Cell(character: ch, style: style)
        if width == 2, let continuation = index(p.x + 1, p.y) {
            clearGlyph(overlapping: continuation)
            back[continuation] = Cell(style: style, isContinuation: true)
        }
    }

    /// Word-wrapped text via the same `TextLayout` the layout engine
    /// measures with — painted height always equals measured height.
    public mutating func putText(_ s: String, at p: Point, style: TextStyle, maxWidth: Int) {
        var y = p.y
        for line in TextLayout.wrap(s, width: maxWidth) {
            var x = p.x
            for ch in line {
                put(ch, at: Point(x: x, y: y), style: style)
                x += TextLayout.cellWidth(of: ch)
            }
            y += 1
        }
    }

    /// Fills `rect` (clipped to the grid) with copies of `cell`.
    public mutating func fill(_ rect: Rect, with cell: Cell) {
        let clipped = rect.intersection(Rect(origin: .zero, size: size))
        for y in clipped.minY..<clipped.maxY {
            for x in clipped.minX..<clipped.maxX {
                if let i = index(x, y) {
                    clearGlyph(overlapping: i)
                    back[i] = cell
                }
            }
        }
    }

    /// Sets only the background color across `rect`, preserving glyphs.
    public mutating func fillBackground(_ rect: Rect, color: Color) {
        let clipped = rect.intersection(Rect(origin: .zero, size: size))
        for y in clipped.minY..<clipped.maxY {
            for x in clipped.minX..<clipped.maxX {
                guard let i = index(x, y) else { continue }
                back[i].style.background = color
            }
        }
    }

    // MARK: Diff → ANSI

    /// Emit minimal escape codes reconciling front→back; swaps buffers.
    public mutating func presentDiff() -> String {
        var out = ""
        out.reserveCapacity(4096)
        var lastStyle: TextStyle? = nil
        var cursor: Point? = nil

        for y in 0..<size.height {
            for x in 0..<size.width {
                let i = y * size.width + x
                let cell = back[i]
                if !forceFull, cell == front[i] { continue }
                if cell.isContinuation { continue }

                if cursor != Point(x: x, y: y) {
                    out += "\u{1B}[\(y + 1);\(x + 1)H"
                }
                if lastStyle != cell.style {
                    out += sgr(for: cell.style)
                    lastStyle = cell.style
                }
                out.append(cell.character)
                cursor = Point(x: x + max(1, TextLayout.cellWidth(of: cell.character)), y: y)
            }
        }

        swap(&front, &back)
        forceFull = false
        return out
    }

    private func sgr(for style: TextStyle) -> String {
        var codes: [String] = ["0"]
        let a = style.attributes
        if a.contains(.bold) { codes.append("1") }
        if a.contains(.dim) { codes.append("2") }
        if a.contains(.italic) { codes.append("3") }
        if a.contains(.underline) { codes.append("4") }
        if a.contains(.inverse) { codes.append("7") }
        if a.contains(.strikethrough) { codes.append("9") }

        if !style.foreground.isDefault {
            let c = style.foreground
            codes.append(
                trueColor ? "38;2;\(c.r);\(c.g);\(c.b)" : "38;5;\(c.xterm256)"
            )
        }
        if !style.background.isDefault {
            let c = style.background
            codes.append(
                trueColor ? "48;2;\(c.r);\(c.g);\(c.b)" : "48;5;\(c.xterm256)"
            )
        }
        return "\u{1B}[\(codes.joined(separator: ";"))m"
    }

    // MARK: Run iteration (GUI/DOM/embed backends)

    /// Read one back-buffer cell (the frame being composed).
    public func cell(atX x: Int, y: Int) -> Cell? {
        guard let i = index(x, y) else { return nil }
        return back[i]
    }

    /// Visit each row as maximal runs of identically-styled cells —
    /// the natural unit for text draws, DOM spans, and rect fills.
    public func forEachRun(
        _ body: (_ row: Int, _ col: Int, _ gridWidth: Int, _ text: String, _ style: TextStyle) -> Void
    ) {
        for y in 0..<size.height {
            var x = 0
            while x < size.width {
                let start = back[y * size.width + x]
                var text = start.isContinuation ? "" : String(start.character)
                var end = x + 1
                while end < size.width {
                    let c = back[y * size.width + end]
                    if c.style != start.style { break }
                    if !c.isContinuation { text.append(c.character) }
                    end += 1
                }
                body(y, x, end - x, text, start.style)
                x = end
            }
        }
    }

    private mutating func clearGlyph(overlapping index: Int) {
        if back[index].isContinuation, index > 0 { back[index - 1] = .blank }
        if !back[index].isContinuation,
            TextLayout.cellWidth(of: back[index].character) == 2,
            index + 1 < back.count, back[index + 1].isContinuation
        {
            back[index + 1] = .blank
        }
        back[index] = .blank
    }

    private static func normalized(_ requested: Size) -> (size: Size, count: Int) {
        guard requested.width >= 0, requested.height >= 0 else { return (.zero, 0) }
        let (count, overflow) = requested.width.multipliedReportingOverflow(by: requested.height)
        guard !overflow, count <= maximumCellCount else { return (.zero, 0) }
        return (requested, count)
    }
}
