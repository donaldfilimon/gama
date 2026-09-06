import Testing

@testable import GamaCore
@testable import GamaDraw

/// A terminal wants a differential ANSI stream; a pipe wants a chronology.
/// These pin the second derivation and prove that naming the shared
/// abstraction left the ANSI path byte-identical.
@Suite("Stream presenter")
struct StreamPresenterTests {
    private func buffer(_ size: Size = Size(width: 20, height: 4)) -> CellBuffer {
        CellBuffer(size: size)
    }

    private func write(_ text: String, row: Int, into b: inout CellBuffer) {
        b.putText(text, at: Point(x: 0, y: row), style: TextStyle(), maxWidth: b.size.width)
    }

    @Test("Only changed rows reach the stream")
    func onlyChangedRows() {
        var b = buffer()
        var p = StreamPresenter()

        write("step 1/3", row: 0, into: &b)
        write("stable", row: 1, into: &b)
        #expect(p.present(&b) == ["step 1/3", "stable"])

        b.clearBack()
        write("step 2/3", row: 0, into: &b)
        write("stable", row: 1, into: &b)
        // Row 1 is unchanged, so it must not repeat.
        #expect(p.present(&b) == ["step 2/3"])
    }

    @Test("An unchanged frame emits nothing")
    func unchangedFrameIsSilent() {
        var b = buffer()
        var p = StreamPresenter()
        write("idle", row: 0, into: &b)
        _ = p.present(&b)

        b.clearBack()
        write("idle", row: 0, into: &b)
        #expect(p.present(&b).isEmpty)
    }

    /// Output is append-only chronology, never a repeated snapshot of the
    /// whole grid, which is what separates this from AccessibilitySnapshot.
    @Test("Output is chronological, not a repeated snapshot")
    func chronologicalNotSnapshot() {
        var b = buffer()
        var p = StreamPresenter()
        write("title", row: 0, into: &b)
        write("0%", row: 2, into: &b)
        _ = p.present(&b)

        var emitted: [String] = []
        for percent in ["25%", "50%", "100%"] {
            b.clearBack()
            write("title", row: 0, into: &b)
            write(percent, row: 2, into: &b)
            emitted += p.present(&b)
        }
        // The unchanging title never repeats.
        #expect(emitted == ["25%", "50%", "100%"])
    }

    @Test("Trailing blank padding is trimmed")
    func trimsTrailingPadding() {
        var b = buffer()
        var p = StreamPresenter()
        write("hi", row: 0, into: &b)
        let lines = p.present(&b)
        #expect(lines == ["hi"])
    }

    /// A row that empties is a change, but an empty line is noise in a log,
    /// so it is dropped rather than emitted blank.
    @Test("A row that becomes empty emits no blank line")
    func emptiedRowIsDropped() {
        var b = buffer()
        var p = StreamPresenter()
        write("gone soon", row: 0, into: &b)
        _ = p.present(&b)

        b.clearBack()
        #expect(p.present(&b).isEmpty)
    }

    /// The abstraction must not have changed the terminal path. Two buffers
    /// fed identically produce identical ANSI before and after conformance.
    @Test("Conforming the ANSI path left its output unchanged")
    func ansiPathUnchanged() {
        var direct = buffer()
        var viaPresenter = buffer()
        var p = AnsiPresenter()

        write("same input", row: 0, into: &direct)
        write("same input", row: 0, into: &viaPresenter)

        let fromMethod = direct.presentDiff()
        let fromProtocol = p.present(&viaPresenter)
        #expect(fromMethod == fromProtocol)
        #expect(fromMethod.isEmpty == false)
    }
}
