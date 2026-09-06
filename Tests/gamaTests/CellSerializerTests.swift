import Testing

@testable import GamaCore
@testable import GamaDraw
@testable import GamaWASM

/// `CellPresenter` reconciles and *swaps*; `CellSerializer` derives a value
/// and leaves the buffer alone. These pin both halves of that distinction:
/// that the wrapper is byte-identical to the free function it names, and
/// that serializing does not advance the buffer the way presenting does.
@Suite("Cell serializer")
struct CellSerializerTests {
    private func painted() -> CellBuffer {
        var b = CellBuffer(size: Size(width: 24, height: 3))
        b.putText(
            "plain row", at: Point(x: 0, y: 0), style: TextStyle(), maxWidth: b.size.width)
        b.putText(
            "bold row", at: Point(x: 0, y: 1),
            style: TextStyle(foreground: .red, attributes: [.bold]), maxWidth: b.size.width)
        b.putText(
            "inverse", at: Point(x: 2, y: 2),
            style: TextStyle(background: .blue, attributes: [.inverse]), maxWidth: b.size.width)
        return b
    }

    @Test("DrawListSerializer equals the free function it wraps")
    func drawListWrapperIsIdentical() {
        let b = painted()
        let viaProtocol = DrawListSerializer().serialize(b)
        let viaFreeFunction = DrawList.from(b)
        #expect(viaProtocol == viaFreeFunction)
    }

    /// The load-bearing difference from ``CellPresenter``. A presenter calls
    /// `presentDiff()`, which swaps the planes, so the next frame sees the
    /// previous one as the front. A serializer must not: `GamaWASM` and
    /// `GamaEmbed` read the back plane whole on every frame and have never
    /// swapped. If `serialize` ever swapped, those backends would start
    /// emitting diffs of themselves.
    @Test("Serializing does not swap the buffer's planes")
    func serializingDoesNotSwap() {
        var b = painted()

        _ = DrawListSerializer().serialize(b)
        _ = DrawListSerializer().serialize(b)

        // Every painted row is still reported as changed, because nothing
        // promoted the back plane to the front. A presenter would have.
        var stream = StreamPresenter()
        let lines = stream.present(&b)
        #expect(lines == ["plain row", "bold row", "  inverse"])
    }

    /// Serializing the same buffer twice must produce the same value; a
    /// serializer holds no frame state, which is why the protocol's
    /// requirement is non-`mutating`.
    @Test("Serialization is repeatable on an unchanged buffer")
    func repeatableOnUnchangedBuffer() {
        let b = painted()
        let serializer = DrawListSerializer()
        #expect(serializer.serialize(b) == serializer.serialize(b))
    }

    /// Nothing in this repository pinned byte-identical HTML before this
    /// case. `WASMSerializerTests` uses `hasPrefix`, `contains`, and range
    /// counts; the browser gate's marker reads `root.textContent` through a
    /// regex, so span structure, the `gama-row` class, and every CSS value
    /// are invisible to it. A rewrite of `css(for:)` would pass both.
    @Test("HTMLSerializer output is pinned exactly")
    func htmlIsByteIdentical() {
        var b = CellBuffer(size: Size(width: 3, height: 1))
        b.putText("hi", at: Point(x: 0, y: 0), style: TextStyle(), maxWidth: 3)
        #expect(
            HTMLSerializer().serialize(b)
                == #"<pre class="gama-row"><span style="">hi </span></pre>"#)
    }

    /// The instance method must be indistinguishable from the static it
    /// forwards to. The statics are deliberately retained so the existing
    /// direct-call tests keep exercising them.
    @Test("HTMLSerializer instance equals its static")
    func htmlWrapperIsIdentical() {
        var b = CellBuffer(size: Size(width: 12, height: 2))
        b.putText("row", at: Point(x: 0, y: 0), style: TextStyle(attributes: [.bold]), maxWidth: 12)
        #expect(HTMLSerializer().serialize(b) == HTMLSerializer.grid(from: b))
    }
}
