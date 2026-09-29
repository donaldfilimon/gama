//  EmbedABITests.swift — additions to the C ABI surface: version
//  interrogation, dimension clamping, and the frame reuse path.
//  (EmbedTests.swift covers the create/input/frame/destroy lifecycle.)

import GamaCore
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
            #expect(throws: Never.self) { try DrawList.decode(frame) }
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
            #expect(throws: Never.self, "round \(round) frame must decode") {
                try DrawList.decode(frame)
            }
            #expect(frame.prefix(4) == [0x47, 0x41, 0x4D, 0x41])  // 'GAMA'
            previous = frame
        }
        #expect(!previous.isEmpty)
    }
}

/// Logs the gestures its one pad receives; a class so the escaping handler
/// can append. `@unchecked Sendable` only so the app value holding it can be
/// `sending` into `makeContext`: the embed contract is single-thread, and
/// every test reads the log on the thread that drove the context.
private final class EmbedGestureLog: @unchecked Sendable {
    var phases: [PointerGesture.Phase] = []
}

/// A 6x3 pad at the origin that opts into pointer gestures.
private struct EmbedPad: View {
    typealias Body = Never_
    var body: Never_ { Never_() }
    let log: EmbedGestureLog

    func render(in context: BuildContext) -> RenderNode {
        let id = context.id
        let log = log
        context.registerPointerHandler(id) { gesture in
            log.phases.append(gesture.phase)
            return true
        }
        return .interactive(
            id: id, focusable: true,
            child: Text("pad").frame(width: 6, height: 3).render(in: context.child(0)))
    }
}

private struct EmbedPadApp: App {
    let log: EmbedGestureLog
    init() { log = EmbedGestureLog() }
    init(log: EmbedGestureLog) { self.log = log }
    var scenes: some Scene {
        Window("Pad", id: "main", role: .primary) { EmbedPad(log: log) }
    }
}

@Suite("Embed pointer ABI (ADR 0018)")
struct EmbedPointerABITests {
    // Wire codes, as GamaEmbed.h names them.
    private let down: Int32 = 0, move: Int32 = 1, up: Int32 = 2, stationary: Int32 = 6

    @Test("pointer_event rejects a null context before validating arguments")
    func nullContextFirst() {
        #expect(gama_embed_v1_pointer_event(nil, 99, 0, 0, 0, 0, 0, 0, 0, 0, -1) == -1)
        var deadline: Int64 = 0
        #expect(gama_embed_v1_pointer_deadline(nil, &deadline) == -1)
    }

    @Test("an invalid phase, kind, button or modifier set is GAMA_EMBED_ERR_INVALID_POINTER")
    func invalidArguments() {
        let context = gama_embed_v1_context_create(20, 6)
        defer { gama_embed_v1_context_destroy(context) }
        #expect(gama_embed_v1_pointer_event(context, 99, 0, 0, 0, 0, 0, 0, 0, 0, -1) == -4)
        #expect(gama_embed_v1_pointer_event(context, 0, 9, 0, 0, 0, 0, 0, 0, 0, -1) == -4)
        #expect(gama_embed_v1_pointer_event(context, 0, 0, -1, 0, 0, 0, 0, 0, 0, -1) == -4)
        #expect(gama_embed_v1_pointer_event(context, 0, 0, 0, 64, 0, 0, 0, 0, 0, -1) == -4)
    }

    @Test("a drag through the C ABI reaches the handler, and the deadline is published")
    func dragAndDeadline() throws {
        let log = EmbedGestureLog()
        let context = try GamaEmbed.makeContext(app: EmbedPadApp(log: log), columns: 20, rows: 6)
        defer { gama_embed_v1_context_destroy(context) }
        var length: Int32 = 0
        _ = gama_embed_v1_frame(context, &length)  // lay out the pad

        var deadline: Int64 = 7
        #expect(gama_embed_v1_pointer_deadline(context, &deadline) == 0)
        #expect(deadline == -1)

        #expect(gama_embed_v1_pointer_event(context, down, 0, 0, 0, 1, 1, 0, 0, 0, 1000) == 0)
        #expect(gama_embed_v1_pointer_deadline(context, &deadline) == 0)
        #expect(deadline == 1500)
        #expect(gama_embed_v1_pointer_event(context, move, 0, 0, 0, 4, 1, 0, 0, 0, 1100) == 0)
        #expect(gama_embed_v1_pointer_event(context, up, 0, 0, 0, 4, 1, 0, 0, 0, 1200) == 0)
        #expect(log.phases == [.pressed, .dragBegan, .dragEnded])
        #expect(gama_embed_v1_pointer_deadline(context, &deadline) == 0)
        #expect(deadline == -1)
    }

    @Test("a stationary sample at the deadline long-presses")
    func stationaryLongPress() throws {
        let log = EmbedGestureLog()
        let context = try GamaEmbed.makeContext(app: EmbedPadApp(log: log), columns: 20, rows: 6)
        defer { gama_embed_v1_context_destroy(context) }
        var length: Int32 = 0
        _ = gama_embed_v1_frame(context, &length)
        #expect(gama_embed_v1_pointer_event(context, down, 0, 0, 0, 1, 1, 0, 0, 0, 1000) == 0)
        #expect(gama_embed_v1_pointer_event(context, stationary, 0, 0, 0, 1, 1, 0, 0, 0, 1500) == 0)
        #expect(log.phases == [.pressed, .longPress])
    }

    @Test("the idiom passed to makeContext sets the policy")
    func idiomReachesTheHost() throws {
        let log = EmbedGestureLog()
        let context = try GamaEmbed.makeContext(
            app: EmbedPadApp(log: log), columns: 20, rows: 6, idiom: .pad)
        defer { gama_embed_v1_context_destroy(context) }
        var length: Int32 = 0
        _ = gama_embed_v1_frame(context, &length)
        var deadline: Int64 = 0
        #expect(gama_embed_v1_pointer_event(context, down, 1, 0, 0, 1, 1, 0, 0, 0, 1000) == 0)
        #expect(gama_embed_v1_pointer_deadline(context, &deadline) == 0)
        #expect(deadline == 1400)
    }
}
