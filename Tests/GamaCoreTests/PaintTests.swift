import Testing
@testable import GamaCore

@Suite
struct PaintTests {
    @Test func buttonSnapshotUnfocused() {
        let node = Button("OK", id: "ok")
        let box = Layout.layout(node, in: Size(width: 10, height: 1))
        var g = CellGrid(width: 10, height: 1)
        Paint.paint(box, into: &g, focus: nil)
        #expect(g.snapshot() == "[ OK ]")
    }

    @Test func focusedButtonIsInverse() {
        let node = Button("OK", id: "ok")
        let box = Layout.layout(node, in: Size(width: 10, height: 1))
        var g = CellGrid(width: 10, height: 1)
        Paint.paint(box, into: &g, focus: "ok")
        #expect(g[0, 0].style.inverse)
    }

    @Test func progressClampsInPaint() {
        var empty = CellGrid(width: 5, height: 1)
        Paint.paint(
            Layout.layout(.progress(0), in: Size(width: 5, height: 1)),
            into: &empty,
            focus: nil
        )
        #expect(empty.snapshot() == "[---]")
        var full = CellGrid(width: 5, height: 1)
        Paint.paint(
            Layout.layout(.progress(1), in: Size(width: 5, height: 1)),
            into: &full,
            focus: nil
        )
        #expect(full.snapshot() == "[###]")
    }
}
