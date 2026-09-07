//  DrawListTests.swift — cell buffer, draw list, and cell painter.

import Testing

@testable import Gama
@testable import GamaCore
@testable import GamaDraw
@testable import GamaMLIR
@testable import GamaTUI

@Suite("Cell buffer")
struct CellBufferTests {
    @Test("equal buffers compare equal")
    func equalBuffersCompareEqual() {
        var left = CellBuffer(size: Size(width: 4, height: 1))
        var right = CellBuffer(size: Size(width: 4, height: 1))
        left.putText("ab", at: .zero, style: .plain, maxWidth: 4)
        right.putText("ab", at: .zero, style: .plain, maxWidth: 4)
        #expect(left == right)
        right.putText("aB", at: .zero, style: .plain, maxWidth: 4)
        #expect(left != right)
    }

    @Test("diff only emits changes")
    func diffOnlyEmitsChanges() {
        var buf = CellBuffer(size: Size(width: 4, height: 1))
        buf.putText("ab", at: .zero, style: .plain, maxWidth: 4)
        let first = buf.presentDiff()
        #expect(!first.isEmpty)

        buf.clearBack()
        buf.putText("ab", at: .zero, style: .plain, maxWidth: 4)
        let second = buf.presentDiff()
        #expect(second.isEmpty, "identical frame should emit nothing")

        buf.clearBack()
        buf.putText("aB", at: .zero, style: .plain, maxWidth: 4)
        let third = buf.presentDiff()
        #expect(third.contains("B"))
        #expect(!third.contains("a"), "unchanged cell should be skipped")
    }
}

@Suite("DrawList")
struct DrawListTests {
    @Test("from buffer skips blank default runs")
    func fromBufferSkipsBlankDefaultRuns() {
        var buf = CellBuffer(size: Size(width: 10, height: 2))
        buf.clearBack()
        buf.putText("hi", at: Point(x: 1, y: 0), style: .plain, maxWidth: 2)
        let list = DrawList.from(buf)
        #expect(list.commands.count == 1)
        guard case .text(let s, let p, _) = list.commands[0] else {
            Issue.record("expected text")
            return
        }
        #expect(s == "hi")
        #expect(p == Point(x: 1, y: 0))
    }

    @Test("from buffer emits background rects")
    func fromBufferEmitsBackgroundRects() {
        var buf = CellBuffer(size: Size(width: 4, height: 1))
        buf.clearBack()
        buf.fillBackground(Rect(x: 0, y: 0, width: 4, height: 1), color: .blue)
        let list = DrawList.from(buf)
        #expect(
            list.commands.contains { cmd in
                if case .fillRect(let r, let c) = cmd {
                    return r == Rect(x: 0, y: 0, width: 4, height: 1) && c == .blue
                }
                return false
            }
        )
        #expect(!list.commands.contains { if case .text = $0 { return true } else { return false } })
    }

    @Test("binary round trip")
    func binaryRoundTrip() throws {
        var style = TextStyle(foreground: .red, background: .blue)
        style.attributes = [.bold, .underline]
        let original = DrawList(
            size: Size(width: 80, height: 24),
            commands: [
                .fillRect(Rect(x: 2, y: 3, width: 10, height: 1), Color(r: 8, g: 16, b: 32)),
                .fillRect(Rect(x: 0, y: 0, width: 80, height: 24), .default),
                .text("héllo — 世界", at: Point(x: 5, y: 7), style: style),
                .text("plain", at: Point(x: 0, y: 0), style: .plain),
            ]
        )
        #expect(try DrawList.decode(original.encode()) == original)
    }

    @Test("v1 golden payload pins magic, version, and field order")
    func v1GoldenPayloadPinsMagicVersionAndFieldOrder() throws {
        // Bytes are laid out from ADR 0005 / the encoder comment, not copied
        // from a prior encode() run, so a field-order change fails this test
        // instead of both sides moving together.
        let style = TextStyle(
            foreground: Color(r: 1, g: 2, b: 3),
            background: .default,
            attributes: .bold
        )
        let list = DrawList(
            size: Size(width: 2, height: 1),
            commands: [
                .fillRect(Rect(x: 0, y: 0, width: 2, height: 1), Color(r: 8, g: 16, b: 32)),
                .text("A", at: Point(x: 0, y: 0), style: style),
            ]
        )
        let golden: [UInt8] = [
            0x47, 0x41, 0x4D, 0x41,  // magic "GAMA" = 0x414D4147 LE
            0x01, 0x00, 0x00, 0x00,  // version 1
            0x02, 0x00, 0x00, 0x00,  // gridW
            0x01, 0x00, 0x00, 0x00,  // gridH
            0x02, 0x00, 0x00, 0x00,  // commandCount
            0x00,  // fillRect
            0x00, 0x00, 0x00, 0x00,  // x
            0x00, 0x00, 0x00, 0x00,  // y
            0x02, 0x00, 0x00, 0x00,  // w
            0x01, 0x00, 0x00, 0x00,  // h
            0x08, 0x10, 0x20, 0x00,  // r,g,b, flags (painted)
            0x01,  // text
            0x00, 0x00, 0x00, 0x00,  // x
            0x00, 0x00, 0x00, 0x00,  // y
            0x01, 0x02, 0x03, 0x00,  // fg r,g,b, flags
            0x00, 0x00, 0x00, 0x01,  // bg default
            0x01, 0x00,  // sgr bold
            0x01, 0x00, 0x00, 0x00,  // utf-8 length
            0x41,  // "A"
        ]
        #expect(list.encode() == golden)
        #expect(try DrawList.decode(golden) == list)
    }

    @Test("decode rejects garbage")
    func decodeRejectsGarbage() {
        #expect(throws: DrawList.DecodeError.truncated) { try DrawList.decode([]) }
        #expect(throws: DrawList.DecodeError.badMagic) { try DrawList.decode([1, 2, 3, 4]) }
        var truncated = DrawList(
            size: Size(width: 1, height: 1),
            commands: [.text("x", at: Point(x: 0, y: 0), style: .plain)]
        ).encode()
        truncated.removeLast()
        #expect(throws: DrawList.DecodeError.truncated) { try DrawList.decode(truncated) }
    }
}

@Suite("Cell painter")
struct CellPainterTests {
    @Test("painter matches direct paint")
    func painterMatchesDirectPaint() {
        let node = RenderNode.border(
            .rounded, style: TextStyle(foreground: .cyan), title: "T",
            child: .text("body", style: .plain)
        )
        let laid = LayoutEngine.layout(node, in: Rect(x: 0, y: 0, width: 12, height: 3))
        var buf = CellBuffer(size: Size(width: 12, height: 3))
        buf.clearBack()
        CellPainter.paint(laid, into: &buf)
        #expect(buf.cell(atX: 0, y: 0)?.character == "╭")
        #expect(buf.cell(atX: 11, y: 2)?.character == "╯")
        var titleCell: Cell?
        for x in 0..<12 {
            if buf.cell(atX: x, y: 0)?.character == "T" {
                titleCell = buf.cell(atX: x, y: 0)
                break
            }
        }
        #expect(titleCell != nil)
        #expect(titleCell?.style.attributes.contains(.bold) == true)
    }
}
