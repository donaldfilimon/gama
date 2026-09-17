import GamaCore
import GamaDraw
import Testing

/// The portable half of the VoiceOver work: turning a painted frame's
/// `DrawList` into reading-order text. No AppKit/UIKit here — the derivation
/// is platform-free on purpose, so it is provable on every host that builds
/// GamaDraw rather than only where an accessibility client exists.
@Suite("Accessibility snapshot")
struct AccessibilitySnapshotTests {
    private func list(
        _ size: Size,
        _ commands: [DrawCommand]
    ) -> DrawList {
        DrawList(size: size, commands: commands)
    }

    private func plainText(_ string: String, x: Int, y: Int) -> DrawCommand {
        .text(string, at: Point(x: x, y: y), style: TextStyle())
    }

    @Test("a single run reads back as its own row, framed at its columns")
    func singleRun() {
        let snapshot = AccessibilitySnapshot.from(
            list(Size(width: 10, height: 3), [plainText("Hi", x: 2, y: 1)]))
        #expect(snapshot.lines.count == 1)
        #expect(snapshot.lines[0].text == "Hi")
        #expect(snapshot.lines[0].frame == Rect(x: 2, y: 1, width: 2, height: 1))
    }

    @Test("two runs on one row join into one line with the gap as spaces")
    func gapsBecomeSpaces() {
        let snapshot = AccessibilitySnapshot.from(
            list(
                Size(width: 12, height: 1),
                [plainText("ab", x: 0, y: 0), plainText("cd", x: 5, y: 0)]))
        #expect(snapshot.lines.count == 1)
        #expect(snapshot.lines[0].text == "ab   cd")
        #expect(snapshot.lines[0].frame == Rect(x: 0, y: 0, width: 7, height: 1))
    }

    @Test("style changes never split a row into two announcements")
    func styleChangeDoesNotSplitTheRow() {
        var bold = TextStyle()
        bold.attributes.insert(.bold)
        let snapshot = AccessibilitySnapshot.from(
            list(
                Size(width: 12, height: 1),
                [
                    plainText("Total: ", x: 0, y: 0),
                    .text("42", at: Point(x: 7, y: 0), style: bold),
                ]))
        #expect(snapshot.lines.count == 1)
        #expect(snapshot.lines[0].text == "Total: 42")
    }

    @Test("a later command paints over an earlier one on shared cells")
    func laterCommandWins() {
        let snapshot = AccessibilitySnapshot.from(
            list(
                Size(width: 8, height: 1),
                [plainText("aaaa", x: 0, y: 0), plainText("XX", x: 1, y: 0)]))
        #expect(snapshot.lines[0].text == "aXXa")
    }

    @Test("a double-width glyph reserves its trailing cell instead of a blank")
    func doubleWidthGlyphReservesItsTail() {
        // U+231A WATCH is two cells wide (TextLayout.cellWidth), so the "x"
        // that follows it sits at column 2, not column 1.
        let snapshot = AccessibilitySnapshot.from(
            list(Size(width: 6, height: 1), [plainText("\u{231A}x", x: 0, y: 0)]))
        #expect(snapshot.lines[0].text == "\u{231A}x")
        #expect(snapshot.lines[0].frame == Rect(x: 0, y: 0, width: 3, height: 1))
    }

    @Test("a run overwritten in a wide glyph's tail still reads deterministically")
    func writingIntoAWideGlyphTail() {
        let snapshot = AccessibilitySnapshot.from(
            list(
                Size(width: 6, height: 1),
                [plainText("\u{231A}", x: 0, y: 0), plainText("z", x: 1, y: 0)]))
        // The tail cell now holds a real glyph, so it is no longer skipped:
        // the row reads as both, in column order, rather than dropping one.
        #expect(snapshot.lines[0].text == "\u{231A}z")
    }

    @Test("a zero-width mark joins the glyph before it rather than taking a cell")
    func zeroWidthMarkJoinsItsGlyph() {
        // e + U+0301 COMBINING ACUTE ACCENT. Swift already treats these as one
        // Character, so the interesting case is the mark arriving as its own
        // element of the string — split across the run boundary.
        let snapshot = AccessibilitySnapshot.from(
            list(
                Size(width: 6, height: 1),
                [plainText("e", x: 0, y: 0), plainText("\u{0301}f", x: 1, y: 0)]))
        #expect(snapshot.lines[0].text == "e\u{0301}f")
        #expect(snapshot.lines[0].frame.size.width == 2)
    }

    @Test("a leading zero-width mark with nothing to join is dropped")
    func orphanZeroWidthMarkIsDropped() {
        let snapshot = AccessibilitySnapshot.from(
            list(Size(width: 6, height: 1), [plainText("\u{0301}a", x: 0, y: 0)]))
        #expect(snapshot.lines[0].text == "a")
    }

    @Test("background fills alone produce no announcement")
    func fillRectsAreNotAnnounced() {
        let snapshot = AccessibilitySnapshot.from(
            list(
                Size(width: 6, height: 2),
                [.fillRect(Rect(x: 0, y: 0, width: 6, height: 2), Color(r: 1, g: 2, b: 3))]))
        #expect(snapshot.lines.isEmpty)
        #expect(snapshot.text.isEmpty)
    }

    @Test("blank rows are skipped, not announced as empty")
    func blankRowsAreSkipped() {
        let snapshot = AccessibilitySnapshot.from(
            list(
                Size(width: 6, height: 4),
                [plainText("top", x: 0, y: 0), plainText("bot", x: 0, y: 3)]))
        #expect(snapshot.lines.map(\.text) == ["top", "bot"])
        #expect(snapshot.lines.map(\.frame.minY) == [0, 3])
    }

    @Test("a run of only spaces is not an announcement")
    func whitespaceOnlyRunIsNotALine() {
        let snapshot = AccessibilitySnapshot.from(
            list(Size(width: 6, height: 1), [plainText("   ", x: 0, y: 0)]))
        #expect(snapshot.lines.isEmpty)
    }

    @Test("lines come back in top-to-bottom reading order regardless of command order")
    func readingOrderIsByRow() {
        let snapshot = AccessibilitySnapshot.from(
            list(
                Size(width: 6, height: 3),
                [
                    plainText("third", x: 0, y: 2),
                    plainText("first", x: 0, y: 0),
                    plainText("2nd", x: 0, y: 1),
                ]))
        #expect(snapshot.lines.map(\.text) == ["first", "2nd", "third"])
        #expect(snapshot.text == "first\n2nd\nthird")
    }

    @Test("a command above or below the grid is clipped away")
    func offGridRowsAreClipped() {
        let snapshot = AccessibilitySnapshot.from(
            list(
                Size(width: 6, height: 2),
                [
                    plainText("above", x: 0, y: -1),
                    plainText("below", x: 0, y: 9),
                    plainText("in", x: 0, y: 0),
                ]))
        #expect(snapshot.lines.map(\.text) == ["in"])
    }

    @Test("a run starting left of the grid resumes at column zero")
    func negativeColumnsAreClipped() {
        let snapshot = AccessibilitySnapshot.from(
            list(Size(width: 6, height: 1), [plainText("abcd", x: -2, y: 0)]))
        #expect(snapshot.lines[0].text == "cd")
        #expect(snapshot.lines[0].frame == Rect(x: 0, y: 0, width: 2, height: 1))
    }

    @Test("a run past the right edge stops at the edge")
    func overflowIsClipped() {
        let snapshot = AccessibilitySnapshot.from(
            list(Size(width: 4, height: 1), [plainText("abcdefgh", x: 2, y: 0)]))
        #expect(snapshot.lines[0].text == "ab")
        #expect(snapshot.lines[0].frame == Rect(x: 2, y: 0, width: 2, height: 1))
    }

    @Test("a zero-sized grid yields nothing rather than trapping")
    func emptyGridIsEmpty() {
        let snapshot = AccessibilitySnapshot.from(
            list(Size(width: 0, height: 0), [plainText("ignored", x: 0, y: 0)]))
        #expect(snapshot.lines.isEmpty)
        #expect(snapshot.size == Size(width: 0, height: 0))
    }

    @Test("the snapshot of a real painted frame matches its visible text")
    func derivedFromARealPaintedFrame() throws {
        struct Demo: App {
            var scenes: some Scene {
                Window("Accessibility", id: "main", role: .primary) {
                    VStack {
                        Text("Alpha")
                        Text("Beta")
                    }
                }
            }
        }
        let size = Size(width: 20, height: 4)
        var host = try FrameHost(app: Demo())
        let laidOut = host.pump(size: size)
        var buffer = CellBuffer(size: size)
        CellPainter.paint(laidOut, into: &buffer)
        let snapshot = AccessibilitySnapshot.from(DrawList.from(buffer))
        #expect(snapshot.lines.contains { $0.text.contains("Alpha") })
        #expect(snapshot.lines.contains { $0.text.contains("Beta") })
    }
}
