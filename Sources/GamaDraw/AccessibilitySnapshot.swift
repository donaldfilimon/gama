//  AccessibilitySnapshot.swift — GamaDraw
//  Reading-order text derived from a painted frame's DrawList, for
//  assistive-technology adapters. Platform-free and stdlib-only, so the
//  derivation is unit-testable without AppKit/UIKit and every host that
//  ships an adapter reads the same frame the same way.

import GamaCore

/// A reading-order view of one rendered frame, derived only from its
/// ``DrawList``.
///
/// Assistive technologies need text in reading order with a position for
/// each fragment; a `DrawList` carries text runs, but a run is a *painting*
/// unit, not a reading unit. A row can be several runs because the style
/// changed mid-line, and the gaps between runs are meaningful whitespace
/// that no single run records.
///
/// This type replays the list's text commands into a character grid — later
/// commands paint over earlier ones, exactly as a renderer would — and reads
/// each row back as one line. That keeps the adapter honest: an
/// accessibility client is told what the frame *shows*, never a second,
/// separately-maintained model of what the application *means*. Interaction
/// semantics stay in `GamaCore` where they are already tested.
///
/// `fillRect` commands are deliberately ignored: a background color is
/// presentation, and announcing it would add noise without adding meaning.
public struct AccessibilitySnapshot: Hashable, Sendable {
    /// One non-blank grid row, as text plus the cell rectangle it occupies.
    public struct Line: Hashable, Sendable {
        /// The row's visible characters, from its first non-blank cell to
        /// its last, with interior gaps preserved as spaces.
        public var text: String
        /// The grid-space cells `text` occupies — always one row tall, and
        /// wide enough to include the trailing cell of a double-width glyph.
        public var frame: Rect

        /// Creates a line occupying `frame` and reading as `text`.
        public init(text: String, frame: Rect) {
            self.text = text
            self.frame = frame
        }
    }

    /// The cell grid the snapshot was derived for.
    public var size: Size
    /// Non-blank rows in reading order, top to bottom. Blank rows are
    /// omitted rather than announced as empty.
    public var lines: [Line]

    /// Creates a snapshot directly; prefer ``from(_:)``.
    public init(size: Size, lines: [Line]) {
        self.size = size
        self.lines = lines
    }

    /// Every line's text joined by newlines — the whole surface as one
    /// string, for hosts that expose a single text value instead of
    /// per-line elements.
    public var text: String {
        var out = ""
        for (index, line) in lines.enumerated() {
            if index > 0 { out.append("\n") }
            out += line.text
        }
        return out
    }

    /// Derives the reading-order snapshot of `list`.
    ///
    /// Text commands are replayed in list order into a grid of
    /// `list.size`, so a later command overwrites an earlier one on the
    /// cells they share — the same precedence a renderer applies. Each
    /// character advances by its `GamaCore.TextLayout.cellWidth(of:)` width,
    /// so a double-width glyph reserves its trailing cell and a zero-width mark
    /// joins the glyph it follows instead of consuming a cell of its own.
    /// Commands positioned outside the grid are clipped away.
    public static func from(_ list: DrawList) -> AccessibilitySnapshot {
        let width = list.size.width
        let height = list.size.height
        guard width > 0, height > 0 else {
            return AccessibilitySnapshot(size: list.size, lines: [])
        }

        // One row of glyph strings plus a parallel "this cell is the tail of
        // a double-width glyph" flag. Strings, not Characters, so a
        // zero-width combining mark can be appended to the glyph it
        // modifies rather than being dropped or given a cell.
        var rows = [[String]](repeating: [String](repeating: " ", count: width), count: height)
        var tails = [[Bool]](repeating: [Bool](repeating: false, count: width), count: height)

        for command in list.commands {
            guard case .text(let string, let origin, _) = command else { continue }
            guard origin.y >= 0, origin.y < height else { continue }
            var column = origin.x
            var lastGlyphColumn: Int? = nil
            for character in string {
                let cellWidth = TextLayout.cellWidth(of: character)
                if cellWidth == 0 {
                    // A combining mark occupies no cell of its own; it
                    // belongs to the glyph to its left, exactly as a terminal
                    // attaches it. That glyph is usually earlier in this same
                    // run, but a style change can put it in the previous
                    // command, so fall back to whatever already occupies the
                    // cell left of the write position — stepping back past a
                    // double-width glyph's tail to reach its head. With
                    // nothing to the left at all the mark is dropped rather
                    // than given a cell it does not occupy.
                    if let anchor = lastGlyphColumn ?? glyphHead(before: column, tails: tails[origin.y]) {
                        rows[origin.y][anchor] += String(character)
                    }
                    continue
                }
                defer { column += cellWidth }
                // Clip rather than wrap: a run that starts left of the grid
                // resumes at column 0, and one that runs past the right edge
                // stops there.
                guard column >= 0 else { continue }
                guard column < width else { break }
                rows[origin.y][column] = String(character)
                tails[origin.y][column] = false
                lastGlyphColumn = column
                for tail in 1..<max(1, cellWidth) where column + tail < width {
                    rows[origin.y][column + tail] = ""
                    tails[origin.y][column + tail] = true
                }
            }
        }

        var lines: [Line] = []
        for row in 0..<height {
            let occupied = { (column: Int) in tails[row][column] || rows[row][column] != " " }
            guard let first = (0..<width).first(where: occupied),
                let last = (0..<width).last(where: occupied)
            else { continue }
            var text = ""
            for column in first...last where !tails[row][column] {
                text += rows[row][column]
            }
            lines.append(
                Line(
                    text: text,
                    frame: Rect(x: first, y: row, width: last - first + 1, height: 1)))
        }
        return AccessibilitySnapshot(size: list.size, lines: lines)
    }

    /// The column holding the glyph that ends immediately left of `column`,
    /// or `nil` when `column` is at or past the left edge. Walks back over a
    /// double-width glyph's trailing cells so the head is returned, never the
    /// tail.
    private static func glyphHead(before column: Int, tails: [Bool]) -> Int? {
        var probe = column - 1
        guard probe >= 0, probe < tails.count else { return nil }
        while probe > 0, tails[probe] { probe -= 1 }
        return probe
    }
}
