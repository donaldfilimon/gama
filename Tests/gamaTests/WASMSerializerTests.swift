//  WASMSerializerTests.swift — HTML/CSS emission of the web backend.
//  HTMLSerializer is pure String code compiled on every platform, so the
//  browser backend's entire visual output is testable without a wasm SDK.

import GamaCore
import GamaDraw
import Testing

@testable import GamaWASM

@Suite("WASM HTML serializer")
struct WASMSerializerTests {
    @Test("Rows wrap in pre elements and default runs merge")
    func gridStructure() {
        var buffer = CellBuffer(size: Size(width: 8, height: 2))
        buffer.clearBack()
        buffer.putText("hi", at: Point(x: 0, y: 0), style: .plain, maxWidth: 8)
        let html = HTMLSerializer.grid(from: buffer)
        #expect(html.hasPrefix("<pre class=\"gama-row\">"))
        #expect(html.hasSuffix("</pre>"))
        #expect(html.contains("hi"))
        // Two rows → exactly two row containers.
        let rowPrefix = "<pre class=\"gama-row\">"
        let rowCount = html.indices.filter { html[$0...].hasPrefix(rowPrefix) }.count
        #expect(rowCount == 2)
    }

    @Test("Text content is entity-escaped")
    func contentEscaping() {
        var buffer = CellBuffer(size: Size(width: 12, height: 1))
        buffer.clearBack()
        buffer.putText("<a&b>", at: Point(x: 0, y: 0), style: .plain, maxWidth: 12)
        let html = HTMLSerializer.grid(from: buffer)
        #expect(html.contains("&lt;a&amp;b&gt;"))
        #expect(!html.contains("<a&b>"))
    }

    @Test("Escape handles the three entity characters and nothing else")
    func escapeFunction() {
        #expect(HTMLSerializer.escape("a<b>c&d\"e'f") == "a&lt;b&gt;c&amp;d\"e'f")
        #expect(HTMLSerializer.escape("plain") == "plain")
        #expect(HTMLSerializer.escape("") == "")
    }

    @Test("CSS covers colors, attributes, and inverse swap")
    func cssEmission() {
        var style = TextStyle(
            foreground: Color(r: 1, g: 2, b: 3), background: Color(r: 9, g: 8, b: 7))
        style.attributes = [.bold, .italic, .underline, .strikethrough, .dim]
        let css = HTMLSerializer.css(for: style)
        #expect(css.contains("color:rgb(1,2,3);"))
        #expect(css.contains("background:rgb(9,8,7);"))
        #expect(css.contains("font-weight:bold;"))
        #expect(css.contains("font-style:italic;"))
        #expect(css.contains("opacity:.6;"))
        #expect(css.contains("text-decoration:underline line-through;"))

        var inverse = TextStyle(foreground: Color(r: 1, g: 2, b: 3), background: .default)
        inverse.attributes = [.inverse]
        let inverseCSS = HTMLSerializer.css(for: inverse)
        // Foreground and background swap under .inverse.
        #expect(inverseCSS.contains("background:rgb(1,2,3);"))
        #expect(!inverseCSS.contains("color:rgb(1,2,3);"))

        #expect(HTMLSerializer.css(for: .plain).isEmpty)
    }
}
