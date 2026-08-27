import Testing

@testable import GamaCore
@testable import GamaDraw

/// Portable proof of the canonical pump contract: eager resize, the clean
/// skip, the follow-up flag, and quit propagation. These are the semantics
/// every backend inherits, so they are pinned once here rather than four
/// times across TUI, WASM, Embed, and AppleUI.
///
/// `HostPump` is `~Copyable`, and the `#expect`/`#require` macros expand to
/// generic helpers constrained to `Copyable`. Every assertion below reads
/// the pump into a local `let` first and asserts on that — the same shape
/// the repo already uses for `FrameHost` and `AppRuntime`.
@Suite("Host pump")
struct HostPumpTests {
    private struct CounterApp: App {
        var scenes: some Scene {
            Window("Main", id: "main", role: .primary) {
                Button("press") {}
            }
        }
    }

    private struct PlainApp: App {
        var scenes: some Scene {
            Window("Main", id: "main", role: .primary) { Text("hello") }
        }
    }

    private func makePump(size: Size = Size(width: 20, height: 5)) throws -> HostPump {
        HostPump(host: try FrameHost(app: PlainApp()), size: size)
    }

    @Test("resize is eager: size and dirty state change before the host sees the event")
    func resizeIsEager() throws {
        var pump = try makePump()
        // Drain the launch frame so the host starts clean.
        _ = pump.advance()
        let cleanBefore = pump.needsFrame
        #expect(cleanBefore == false)

        let grown = Size(width: 40, height: 12)
        pump.handle(.resize(grown))

        // Both facts must hold immediately — not at the next pump. This is
        // the exact divergence the unification removes: TUI and AppleUI
        // used to report the old size here.
        let sizeAfter = pump.size
        let dirtyAfter = pump.needsFrame
        #expect(sizeAfter == grown)
        #expect(dirtyAfter)
    }

    @Test("a resized pump lays out at the new extent on the very next advance")
    func advanceUsesTheEagerSize() throws {
        var pump = try makePump()
        _ = pump.advance()

        pump.handle(.resize(Size(width: 33, height: 7)))
        let advanced = pump.advance()
        let frame = try #require(advanced).frame

        #expect(frame.frame.size == Size(width: 33, height: 7))
    }

    @Test("a clean host produces nothing and touches no buffer")
    func cleanHostSkips() throws {
        var pump = try makePump()
        _ = pump.advance()
        let clean = pump.needsFrame
        #expect(clean == false)

        let nothing = pump.advance()
        #expect(nothing == nil)

        var buffer = CellBuffer(size: Size(width: 1, height: 1))
        var emitted = false
        let outcome = pump.advance(into: &buffer) { _ in emitted = true }

        #expect(outcome == .clean)
        #expect(outcome.produced == false)
        #expect(emitted == false)
        // The clean skip must not resize the buffer either.
        #expect(buffer.size == Size(width: 1, height: 1))
    }

    @Test("the buffer path resizes, paints, and emits exactly once per dirty step")
    func bufferPathPaintsAndEmits() throws {
        var pump = try makePump(size: Size(width: 12, height: 3))
        var buffer = CellBuffer(size: Size(width: 1, height: 1))
        var emitCount = 0
        var sizeSeenByEmit = Size.zero

        let outcome = pump.advance(into: &buffer) { painted in
            emitCount += 1
            sizeSeenByEmit = painted.size
        }

        #expect(outcome.produced)
        #expect(emitCount == 1)
        // The buffer handed to emit is already sized and painted.
        #expect(sizeSeenByEmit == Size(width: 12, height: 3))
        #expect(buffer.size == Size(width: 12, height: 3))

        // Second call on a now-clean host emits nothing more.
        let second = pump.advance(into: &buffer) { _ in emitCount += 1 }
        #expect(second == .clean)
        #expect(emitCount == 1)
    }

    @Test("focus reconciliation raises followUp so the frame is not stranded")
    func followUpFlagIsReported() throws {
        var pump = HostPump(
            host: try FrameHost(app: CounterApp()),
            size: Size(width: 20, height: 5))

        // The first advance reconciles focus onto the button. Whatever the
        // host reports as still-dirty must be surfaced verbatim, because
        // that is the signal WASM used to special-case as requestFrame.
        let advanced = pump.advance()
        let followUp = try #require(advanced).followUp
        let stillDirty = pump.needsFrame
        #expect(followUp == stillDirty)
    }

    @Test("quit propagates from the host through the pump")
    func quitPropagates() throws {
        var pump = try makePump()
        let quitBefore = pump.wantsQuit
        #expect(quitBefore == false)

        pump.handle(.key(.ctrl("c")))

        let quitAfter = pump.wantsQuit
        #expect(quitAfter)
    }

    @Test("non-resize events are forwarded without the pump reinterpreting them")
    func otherEventsForwardUntouched() throws {
        var pump = try makePump()
        _ = pump.advance()
        let sizeBefore = pump.size

        pump.handle(.tick)

        // `.tick` is explicitly a no-op in the host: the pump must not
        // invent dirtiness or change size for it.
        let sizeAfter = pump.size
        let dirtyAfter = pump.needsFrame
        #expect(sizeAfter == sizeBefore)
        #expect(dirtyAfter == false)
    }

    @Test("out-of-band invalidate reopens the dirty gate")
    func invalidateReopensTheGate() throws {
        var pump = try makePump()
        _ = pump.advance()
        let cleanBefore = pump.needsFrame
        #expect(cleanBefore == false)

        pump.invalidate()

        let dirtyAfter = pump.needsFrame
        #expect(dirtyAfter)
        let produced = pump.advance()
        #expect(produced != nil)
    }

    @Test("a clamped extent does not re-allocate the buffer every frame")
    func clampedExtentDoesNotThrash() throws {
        // Above CellBuffer.maximumCellCount, so the grid is normalized and
        // buffer.size never equals the requested size. A naive comparison
        // would resize — and force a full present — on every frame.
        let huge = Size(width: 1_000_000, height: 1_000_000)
        var pump = try makePump()
        var buffer = CellBuffer(size: Size(width: 4, height: 4))

        pump.handle(.resize(huge))
        _ = pump.advance(into: &buffer) { _ in }
        let settled = buffer.size

        pump.invalidate()
        _ = pump.advance(into: &buffer) { _ in }

        #expect(buffer.size == settled)
        #expect(buffer.resizeIfNeeded(huge) == false)
    }
}
