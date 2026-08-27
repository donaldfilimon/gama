//  EmbedABITests.swift — additions to the C ABI surface: version
//  interrogation, dimension clamping, and the frame reuse path.
//  (EmbedTests.swift covers the create/input/frame/destroy lifecycle.)

import GamaDraw
import Testing

@testable import GamaEmbed

@Suite("Embed ABI additions")
struct EmbedABITests {
    @Test("ABI version is interrogable and equals 1")
    func abiVersion() {
        #expect(gama_embed_v1_abi_version() == 1)
    }

    @Test("Hostile resize dimensions are clamped, and frames stay valid")
    func hostileResizeClamped() {
        let context = gama_embed_v1_context_create(40, 12)
        defer { gama_embed_v1_context_destroy(context) }
        // Upper clamp: must not attempt an Int32.max × Int32.max grid.
        #expect(gama_embed_v1_resize(context, Int32.max, Int32.max) == 0)
        // Lower clamp mirrors the documented floor of one.
        #expect(gama_embed_v1_resize(context, -5, 0) == 0)
        #expect(gama_embed_v1_resize(context, 40, 12) == 0)
        var length: Int32 = 0
        let bytes = gama_embed_v1_frame(context, &length)
        #expect(bytes != nil)
        #expect(length >= 20)
        if let bytes {
            let frame = Array(UnsafeBufferPointer(start: bytes, count: Int(length)))
            #expect(DrawList.decode(frame) != nil)
        }
    }

    @Test("Frame storage is reused across frames without corruption")
    func frameStorageReuse() {
        let context = gama_embed_v1_context_create(30, 8)
        defer { gama_embed_v1_context_destroy(context) }
        var previous: [UInt8] = []
        for round in 0..<3 {
            // Tab then Enter drives focus + the diagnostic app's counter,
            // dirtying the host so every round produces a frame.
            #expect(gama_embed_v1_key(context, 7, 0, 0, 0) == 0)
            #expect(gama_embed_v1_key(context, 5, 0, 0, 0) == 0)
            var length: Int32 = 0
            let bytes = gama_embed_v1_frame(context, &length)
            #expect(bytes != nil, "round \(round) produced no frame")
            guard let bytes else { continue }
            let frame = Array(UnsafeBufferPointer(start: bytes, count: Int(length)))
            #expect(DrawList.decode(frame) != nil, "round \(round) frame must decode")
            #expect(frame.prefix(4) == [0x47, 0x41, 0x4D, 0x41])  // 'GAMA'
            previous = frame
        }
        #expect(!previous.isEmpty)
    }
}
