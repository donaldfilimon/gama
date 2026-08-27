//  ModernTests.swift — Swift Testing suites for DrawList codec and painter.

import Testing

@testable import GamaCore
@testable import GamaDraw

@Suite("DrawList codec")
struct DrawListCodecSuite {
    @Test("round-trips every attribute bit")
    func attributeBits() {
        let all: [TextAttributes] = [.bold, .dim, .italic, .underline, .inverse, .strikethrough]
        for attr in all {
            var style = TextStyle()
            style.attributes = [attr]
            let list = DrawList(
                size: Size(width: 3, height: 1),
                commands: [.text("x", at: Point(x: 0, y: 0), style: style)])
            #expect(DrawList.decode(list.encode()) == list)
        }
    }

    @Test("header magic gates decoding")
    func magic() {
        var bytes = DrawList(size: Size(width: 1, height: 1)).encode()
        bytes[0] ^= 0xFF
        #expect(DrawList.decode(bytes) == nil)
    }

    @Test("empty frame encodes to header only")
    func emptyFrame() {
        let list = DrawList(size: Size(width: 40, height: 12))
        #expect(list.encode().count == 4 + 4 + 4 + 4 + 4)
        #expect(DrawList.decode(list.encode()) == list)
    }

    @Test("rejects hostile counts, negative geometry, and trailing bytes")
    func malformedPayloads() {
        var hostileCount = DrawList(size: .zero).encode()
        hostileCount[16...19] = [0xff, 0xff, 0xff, 0xff]
        #expect(DrawList.decode(hostileCount) == nil)

        var negativeSize = DrawList(size: .zero).encode()
        negativeSize[8...11] = [0xff, 0xff, 0xff, 0xff]
        #expect(DrawList.decode(negativeSize) == nil)

        var trailing = DrawList(size: .zero).encode()
        trailing.append(0)
        #expect(DrawList.decode(trailing) == nil)
    }

    @Test("rejects every major class of malformed UTF-8")
    func malformedUTF8() {
        let valid = DrawList(
            size: Size(width: 1, height: 1),
            commands: [.text("x", at: .zero, style: .plain)]
        ).encode()
        // One text command places its byte length at 39 and payload at 43.
        let invalidPayloads: [[UInt8]] = [
            [0x80],                    // isolated continuation
            [0xc0, 0xaf],              // overlong encoding
            [0xe2, 0x82],              // truncated multibyte scalar
            [0xed, 0xa0, 0x80],        // UTF-16 surrogate range
            [0xf4, 0x90, 0x80, 0x80],  // above U+10FFFF
        ]
        for payload in invalidPayloads {
            var bytes = valid
            bytes[39...42] = [UInt8(payload.count), 0, 0, 0]
            bytes.replaceSubrange(43..., with: payload)
            #expect(DrawList.decode(bytes) == nil)
        }
    }

    @Test("encoding clamps geometry to the stable 32-bit wire ABI")
    func wireGeometryClamping() {
        let frame = DrawList(
            size: Size(width: .max, height: .max),
            commands: [
                .fillRect(Rect(x: .min, y: .max, width: .max, height: 1), .red)
            ]
        )
        let decoded = DrawList.decode(frame.encode())
        #expect(decoded?.size == Size(width: Int(Int32.max), height: Int(Int32.max)))
        if case .fillRect(let bounds, _)? = decoded?.commands.first {
            #expect(bounds.minX == Int(Int32.min))
            #expect(bounds.minY == Int(Int32.max))
            #expect(bounds.size.width == Int(Int32.max))
        } else {
            Issue.record("expected a clamped fill command")
        }
    }

    @Test("deterministic randomized frames round-trip")
    func randomizedRoundTrips() {
        var state: UInt64 = 0x4741_4D41_0000_0001
        func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state
        }

        for _ in 0..<256 {
            let width = Int(next() % 80)
            let height = Int(next() % 40)
            var commands: [DrawCommand] = []
            for index in 0..<Int(next() % 24) {
                let x = width == 0 ? 0 : Int(next() % UInt64(width))
                let y = height == 0 ? 0 : Int(next() % UInt64(height))
                let color = Color(
                    r: UInt8(truncatingIfNeeded: next()),
                    g: UInt8(truncatingIfNeeded: next() >> 8),
                    b: UInt8(truncatingIfNeeded: next() >> 16)
                )
                let style = TextStyle(foreground: color, attributes: index.isMultiple(of: 2) ? [.bold] : [])
                commands.append(.text("row-\(index)-🙂", at: Point(x: x, y: y), style: style))
            }
            let frame = DrawList(size: Size(width: width, height: height), commands: commands)
            #expect(DrawList.decode(frame.encode()) == frame)
        }
    }
}

@Suite("Overflow-safe geometry")
struct GeometryOverflowSuite {
    @Test("point and rectangle arithmetic saturates")
    func saturation() {
        #expect((Point(x: .max, y: .min) + Point(x: 1, y: -1)) == Point(x: .max, y: .min))
        #expect(Rect(x: .max - 2, y: 0, width: 20, height: 1).maxX == .max)
        #expect(Size(width: -4, height: 8).clamped(to: Size(width: 9, height: -1)) == .zero)
    }

    @Test("empty and extreme intersections stay nonnegative")
    func intersections() {
        let extreme = Rect(x: .max - 4, y: .max - 4, width: .max, height: .max)
        let overlap = extreme.intersection(Rect(x: .max - 2, y: .max - 2, width: 8, height: 8))
        #expect(overlap.size.width == 2)
        #expect(overlap.size.height == 2)
        #expect(Rect(x: 0, y: 0, width: -1, height: 3).intersection(.zero) == .zero)
    }
}

@Suite("CellPainter ↔ DrawList")
struct PainterVectorizeSuite {
    @Test("painted text vectorizes to a single run")
    func singleRun() {
        let node = RenderNode.text("hello", style: TextStyle(foreground: .green))
        let laid = LayoutEngine.layout(node, in: Rect(x: 0, y: 0, width: 10, height: 1))
        var buf = CellBuffer(size: Size(width: 10, height: 1))
        buf.clearBack()
        CellPainter.paint(laid, into: &buf)
        let list = DrawList.from(buf)
        #expect(list.commands.count == 1)
        if case .text(let s, _, let style) = list.commands[0] {
            #expect(s == "hello")
            #expect(style.foreground == .green)
        } else {
            Issue.record("expected a text command")
        }
    }

    @Test("wide and combining graphemes retain grid geometry")
    func unicodeGridGeometry() {
        var buffer = CellBuffer(size: Size(width: 5, height: 1))
        buffer.putText("界e\u{301}", at: .zero, style: .plain, maxWidth: 5)
        #expect(buffer.cell(atX: 0, y: 0)?.character == "界")
        #expect(buffer.cell(atX: 1, y: 0)?.isContinuation == true)
        #expect(buffer.cell(atX: 2, y: 0)?.character == "e\u{301}")
        let list = DrawList.from(buffer)
        #expect(list.commands.contains { command in
            if case .text(let text, let point, _) = command {
                return text == "界e\u{301}" && point == .zero
            }
            return false
        })
    }

    @Test("wide graphemes clip rather than overflow the final column")
    func wideClipping() {
        var buffer = CellBuffer(size: Size(width: 2, height: 1))
        buffer.put("界", at: Point(x: 1, y: 0), style: .plain)
        #expect(buffer.cell(atX: 1, y: 0) == .blank)
        #expect(DrawList.from(buffer).commands.isEmpty)
    }

    @Test("invalid and overflowing buffers normalize without allocation")
    func allocationSafety() {
        #expect(CellBuffer(size: Size(width: -1, height: 4)).size == .zero)
        #expect(CellBuffer(size: Size(width: .max, height: 2)).size == .zero)
        #expect(
            CellBuffer(size: Size(width: CellBuffer.maximumCellCount + 1, height: 1)).size
                == .zero)
    }
}
