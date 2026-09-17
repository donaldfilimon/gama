//  P1LayoutTests.swift — Codex P1 regressions: border titles, divider axis,
//  TextField C0, emoji-presentation width, and Button focus vs label color.

import GamaCore
import GamaDraw
import Testing

private func painted(
    _ node: RenderNode, size: Size? = nil
) -> (Size, CellBuffer) {
    let measured = size ?? LayoutEngine.measure(node, proposal: .unspecified)
    let laid = LayoutEngine.layout(
        node, in: Rect(origin: .zero, size: measured))
    var buffer = CellBuffer(size: measured)
    buffer.clearBack()
    CellPainter.paint(laid, into: &buffer)
    return (measured, buffer)
}

private func characters(in buffer: CellBuffer, row: Int) -> String {
    var out = ""
    for x in 0..<buffer.size.width {
        if let cell = buffer.cell(atX: x, y: row), !cell.isContinuation {
            out.append(cell.character)
        }
    }
    return out
}

@Suite("Border title")
struct BorderTitleTests {
    @Test("natural width is exactly the padded caption width")
    func naturalSizeTitleFillsReservedTopEdge() {
        let node = RenderNode.border(
            .rounded, style: .plain, title: "T",
            child: .text("x", style: .plain)
        )
        let (size, buffer) = painted(node)
        #expect(size.width == TextLayout.displayWidth(of: "T") + 4)
        #expect(characters(in: buffer, row: 0) == "╭ T ╮")
    }

    @Test("wide and combining graphemes keep display-cell sizing")
    func unicodeTitleUsesDisplayWidth() {
        let title = "界e\u{301}"
        let node = RenderNode.border(
            .rounded, style: .plain, title: title,
            child: .text("x", style: .plain)
        )
        let (size, buffer) = painted(node)
        #expect(TextLayout.displayWidth(of: title) == 3)
        #expect(size.width == 7)
        #expect(characters(in: buffer, row: 0) == "╭ 界e\u{301} ╮")
    }

    @Test("empty caption adds no title padding")
    func emptyTitleDoesNotReserveBlankSpace() {
        let node = RenderNode.border(
            .rounded, style: .plain, title: "",
            child: .text("x", style: .plain)
        )
        let (size, buffer) = painted(node)
        #expect(size.width == 3)
        #expect(characters(in: buffer, row: 0) == "╭─╮")
    }
}

@Suite("Divider axis")
struct DividerAxisTests {
    @Test("HStack divider in a 1×1 frame paints the vertical glyph")
    func hStackSquareDividerIsVertical() {
        let ir = HStack { Divider() }.render(in: BuildContext(id: .root))
        let laid = LayoutEngine.layout(
            ir, in: Rect(x: 0, y: 0, width: 1, height: 1))
        var buffer = CellBuffer(size: Size(width: 1, height: 1))
        buffer.clearBack()
        CellPainter.paint(laid, into: &buffer)
        #expect(buffer.cell(atX: 0, y: 0)?.character == "│")
    }
}

@Suite("TextField C0")
struct TextFieldControlTests {
    private struct FieldApp: App {
        let text = Signal("ab")
        init() {}
        var scenes: some Scene {
            Window("Field", id: "main", role: .primary) {
                TextField("Name", text: text.binding())
            }
        }
    }

    @Test("newline from a character event is consumed and not inserted")
    func newlineIsNotInserted() throws {
        let app = FieldApp()
        var host = try FrameHost(app: app)
        _ = host.pump(size: Size(width: 20, height: 3))
        host.handle(.key(.tab))
        _ = host.pump(size: Size(width: 20, height: 3))
        host.handle(.key(.character("\n")))
        let value = app.text.get()
        #expect(value == "ab")
        #expect(!value.contains("\n"))
    }
}

@Suite("TextLayout emoji presentation")
struct TextLayoutEmojiTests {
    @Test("U+231A WATCH occupies two cells")
    func watchIsWide() {
        #expect(TextLayout.cellWidth(of: "⌚") == 2)
        #expect(TextLayout.displayWidth(of: "⌚") == 2)
    }
}

@Suite("Button focus vs label")
struct ButtonFocusStyleTests {
    private struct ColoredButtonApp: App {
        var scenes: some Scene {
            Window("Button", id: "main", role: .primary) {
                Button(action: {}) { Text("go").foregroundColor(.red) }
            }
        }
    }

    @Test("focus wrap wins over a custom-colored label")
    func focusWrapWinsOverLabelColor() throws {
        var host = try FrameHost(app: ColoredButtonApp())
        _ = host.pump(size: Size(width: 12, height: 3))
        host.handle(.key(.tab))
        let laid = host.pump(size: Size(width: 12, height: 3))
        var buffer = CellBuffer(size: Size(width: 12, height: 3))
        buffer.clearBack()
        CellPainter.paint(laid, into: &buffer)
        var sawFocus = false
        for y in 0..<buffer.size.height {
            for x in 0..<buffer.size.width {
                if let cell = buffer.cell(atX: x, y: y),
                    cell.character != " ",
                    cell.style.background == .cyan
                {
                    sawFocus = true
                    #expect(cell.style.foreground == .black)
                }
            }
        }
        #expect(sawFocus)
    }
}
